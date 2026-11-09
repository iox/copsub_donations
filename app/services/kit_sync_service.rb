# Keeps the donor list (this app) and Kit.com (our newsletter tool) 100% in
# sync. Two independent things are synchronized:
#
#  * Newsletter status (donors.mailchimp_status, alias newsletter_status).
#    KIT IS THE SOURCE OF TRUTH: people subscribe, confirm and unsubscribe in
#    Kit, and our database mirrors Kit's state for everyone who is in Kit.
#    The one exception is the donation form opt-in, which creates the Kit
#    subscriber from here. Donors marked 'subscribed' here who are missing in
#    Kit are created there.
#
#  * Donor data (donors.role and donation history). OUR DATABASE IS THE SOURCE
#    OF TRUTH, and Kit gets:
#      - custom field 'role'             (subscriber / single_supporter /
#                                         recurring_supporter / inactive_supporter)
#      - custom field 'mailchimp_status' (the newsletter status, for segments)
#      - exactly one category tag, behind the three Kit segments:
#          "Currently donating (past 3 months)"    -> tag currently_donating
#          "Past donors (donated more than 3 ...)"  -> tag past_donor
#          "Never donated (just subscribed)"       -> tag newsletter_subscriber
#
# Nothing else in Kit is ever changed: no other tags, no other custom fields.
#
# People removed from Kit (deleted in the Kit UI after unsubscribing, to stay
# under the plan limit) keep their 'unsubscribed' status here, so they are
# never added again.
class KitSyncService

  # Category tags (Kit dashboard -> Subscribers -> Tags); one segment each.
  CATEGORY_TAGS = {
    'current'    => 24733359, # tag name: currently_donating
    'past'       => 24733350, # tag name: past_donor
    'newsletter' => 24733357, # tag name: newsletter_subscriber
  }
  CATEGORY_TAG_NAMES = {
    24733359 => 'currently_donating',
    24733350 => 'past_donor',
    24733357 => 'newsletter_subscriber',
  }

  # When donors share an email address, the "best" category / role wins.
  CATEGORY_PRIORITY = %w(current past newsletter)
  ROLE_PRIORITY = %w(recurring_supporter single_supporter inactive_supporter subscriber)

  # Kit subscriber state => our newsletter status. One to one.
  STATE_TO_STATUS = {
    'active'     => 'subscribed',
    'inactive'   => 'pending',      # double opt-in not confirmed yet
    'cancelled'  => 'unsubscribed',
    'bounced'    => 'bounced',
    'complained' => 'complained',
  }

  # Kit states in which a subscriber no longer receives emails.
  KIT_ENDED_STATES = %w(cancelled bounced complained)

  # Kit custom fields kept in sync from our database.
  SYNCED_FIELDS = %w(role mailchimp_status)

  # Candidate Kit changes are confirmed live (one API read each) only up to
  # this many; see #plan.
  LIVE_CHECK_LIMIT = 300

  # Kit subscribers created before this moment come from the October 2026
  # bulk import, whose 'active' states were not reliable. Only used by the
  # one-off cleanup (rake kit:cleanup).
  KIT_IMPORT_CUTOFF = Time.utc(2026, 10, 17)

  class << self

    def client
      @client ||= KitClient.new
    end

    # ------------------------------------------------------------------------
    # Real time
    # ------------------------------------------------------------------------

    # Explicit newsletter opt-in (donation form checkbox): creates the Kit
    # subscriber right away, with segment tag and fields, so they get the very
    # next newsletter. If this fails, the nightly sync creates them.
    def subscribe_to_newsletter(email_address, first_name = nil, donor = nil)
      return if email_address.blank?
      subscriber = create_in_kit(email_address, first_name, donor)

      # Also join the newsletter form, for its welcome automation. Kit answers
      # 404 for this form type through the API; that must not undo the above.
      begin
        client.add_subscriber_to_form_by_email(KIT_NEWSLETTER_FORM_ID, email_address.strip)
      rescue KitClient::Error => e
        Rails.logger.info "Kit: #{email_address} not added to form #{KIT_NEWSLETTER_FORM_ID}: #{e.message}"
      end
      subscriber
    end

    # Creates (or updates) a Kit subscriber with category tag and fields.
    # Only for people who opted in.
    def create_in_kit(email_address, first_name, donor)
      subscriber = client.upsert_subscriber(email_address.strip, :first_name => first_name)
      category = donor ? donor_category(donor) : 'newsletter'
      client.tag_subscriber(CATEGORY_TAGS[category], subscriber['id'])
      fields = { 'mailchimp_status' => 'subscribed' }
      fields['role'] = donor.role if donor && donor.role.present?
      client.update_subscriber(subscriber['id'], subscriber['email_address'] || email_address.strip, :fields => fields)
      subscriber
    end

    # Kit webhooks: applies a subscriber's new state to every donor with that
    # email address (creating one if unknown). Returns the first affected
    # donor, or nil when nothing changed.
    def apply_subscriber_state(email_address, kit_state, first_name = nil)
      status = STATE_TO_STATUS[kit_state.to_s]
      return nil if status.nil? || email_address.blank?

      donors = Donor.find_by_any_email(email_address).to_a
      return create_donor_from_kit(email_address, first_name, status) if donors.empty?

      changed = donors.select { |donor| set_donor_status(donor, status) }
      changed.first
    end

    def create_donor_from_kit(email_address, first_name, status)
      donor = Donor.new(:user_email => email_address.strip, :role => 'subscriber')
      # mailchimp_status / donated_last_year_in_dkk are NOT attr_accessible,
      # so they must be assigned with direct setters (mass assignment would
      # silently drop them).
      donor.mailchimp_status = status
      donor.donated_last_year_in_dkk = 0
      donor.first_name = first_name if first_name.present?
      donor.save
      donor
    end

    # Sets the newsletter status. Never touches the role (donor type).
    # Returns true if it changed.
    def set_donor_status(donor, status)
      return false if donor.mailchimp_status == status
      donor.mailchimp_status = status # direct setter: not attr_accessible
      donor.save
      true
    end

    # ------------------------------------------------------------------------
    # Donor data
    # ------------------------------------------------------------------------

    # 'current' if the donor donated in the last 92 days, 'past' if they ever
    # donated, 'newsletter' if they only subscribed. Same rules as the
    # segmentation used in the October 2026 import.
    def donor_category(donor)
      if donor.donated_total.to_i > 0 && donor.last_donated_at.present?
        (Date.today - donor.last_donated_at).to_i <= 92 ? 'current' : 'past'
      else
        'newsletter'
      end
    end

    def category_reason(donor)
      return 'no donor record here: never donated' if donor.nil?
      return 'never donated' if donor_category(donor) == 'newsletter'
      "last donation #{donor.last_donated_at}"
    end

    def best_role(donors)
      roles = donors.map(&:role).select(&:present?)
      roles.min_by { |role| ROLE_PRIORITY.index(role) || ROLE_PRIORITY.size }
    end

    # ------------------------------------------------------------------------
    # Nightly sync. #plan only reads (Kit snapshots, plus a live check of each
    # candidate change, because Kit's listings lag behind); #apply_plan
    # executes exactly that plan. The dry run prints the plan and stops.
    #
    #   subscribers:    KitClient#all_subscribers (downcased email => subscriber)
    #   category_tags:  KitClient#subscriber_ids_by_tag(CATEGORY_TAGS.values)
    #   live_check:     false for a quick, approximate audit
    # ------------------------------------------------------------------------
    def plan(donors, subscribers, category_tags, live_check: true)
      plan = { :new_donors => [], :status_changes => [], :create_in_kit => [],
               :field_updates => [], :tag_moves => [] }

      by_email = donors.group_by { |d| d.user_email.to_s.strip.downcase }
      by_email.delete('')

      # A + B. Our database: newsletter status follows Kit, for everyone in Kit.
      kit_donors = {}         # Kit email => donors behind it
      matched_ids = Set.new   # donors that have a Kit subscriber
      subscribers.each do |email, sub|
        status = STATE_TO_STATUS[sub['state'].to_s]
        next if status.nil?
        group = by_email[email] || Donor.find_by_any_email(email).to_a
        if group.empty?
          plan[:new_donors] << { :email => email, :status => status, :first_name => sub['first_name'],
                                 :kit_created_at => sub['created_at'] }
          next
        end
        kit_donors[email] = group
        group.each do |donor|
          matched_ids << donor.id
          next if donor.mailchimp_status == status
          plan[:status_changes] << { :donor => donor, :email => email, :from => donor.mailchimp_status,
                                     :to => status }
        end
      end

      # C. Kit: create donors who are subscribed here but missing in Kit.
      by_email.each do |email, group|
        next if subscribers[email] || group.any? { |d| matched_ids.include?(d.id) }
        next unless group.any? { |d| d.mailchimp_status == 'subscribed' }
        donor = group.min_by { |d| CATEGORY_PRIORITY.index(donor_category(d)) }
        plan[:create_in_kit] << { :email => email, :donor => donor, :role => best_role(group) }
      end

      # D + E. Kit: custom fields and category tag of everyone still receiving.
      # First from the snapshots; then, if there are few candidates (a normal
      # night), each one is confirmed live, because Kit's listings lag behind
      # by minutes. A big first run skips that: the lag does not matter there.
      field_candidates = []
      tag_candidates = []
      subscribers.each do |email, sub|
        next if KIT_ENDED_STATES.include?(sub['state'])
        group = kit_donors[email] || []

        desired = { 'role' => best_role(group) || 'subscriber',
                    'mailchimp_status' => STATE_TO_STATUS[sub['state'].to_s] }
        snapshot_fields = sub['fields'] || {}
        diff = desired.reject { |key, value| snapshot_fields[key].to_s == value.to_s }
        field_candidates << [email, sub, desired, snapshot_fields] if diff.any?

        donor = group.min_by { |d| CATEGORY_PRIORITY.index(donor_category(d)) }
        wanted = CATEGORY_TAGS[donor ? donor_category(donor) : 'newsletter']
        current_tags = (category_tags[sub['id']] || Set.new).to_a
        tag_candidates << [email, sub, wanted, current_tags, donor] unless current_tags == [wanted]
      end

      verify = live_check && (field_candidates.size + tag_candidates.size) <= LIVE_CHECK_LIMIT
      plan[:live_checked] = verify

      field_candidates.each do |email, sub, desired, current_fields|
        current_fields = (client.subscriber_by_id(sub['id']) || {})['fields'] || {} if verify
        diff = desired.reject { |key, value| current_fields[key].to_s == value.to_s }
        next if diff.empty?
        plan[:field_updates] << { :email => email, :subscriber_id => sub['id'], :kit_email => sub['email_address'],
                                  :fields => diff, :from => current_fields.slice(*diff.keys) }
      end

      tag_candidates.each do |email, sub, wanted, current_tags, donor|
        current_tags = client.tags_for_subscriber(sub['id']).map { |t| t['id'] } & CATEGORY_TAGS.values if verify
        add = current_tags.include?(wanted) ? [] : [wanted]
        remove = current_tags - [wanted]
        next if add.empty? && remove.empty?
        plan[:tag_moves] << { :email => email, :subscriber_id => sub['id'], :add => add, :remove => remove,
                              :reason => category_reason(donor) }
      end

      plan
    end

    def kit_writes(plan)
      plan[:create_in_kit].size * 3 + plan[:field_updates].size +
        plan[:tag_moves].sum { |m| m[:add].size + m[:remove].size }
    end

    def print_plan(plan, subscribers, log = $stdout)
      tag = ->(ids) { ids.map { |id| CATEGORY_TAG_NAMES[id] }.join(', ') }

      log.puts
      log.puts "A. OUR DATABASE: #{plan[:new_donors].size} new donor record(s) (in Kit, unknown here)"
      plan[:new_donors].sort_by { |n| n[:email] }.each do |n|
        log.puts "     + #{n[:email]}  (#{n[:status]}, in Kit since #{n[:kit_created_at].to_s[0, 10]})"
      end

      log.puts
      log.puts "B. OUR DATABASE: #{plan[:status_changes].size} newsletter status change(s), following Kit"
      plan[:status_changes].group_by { |c| [c[:from], c[:to]] }.sort_by { |_, l| -l.size }.each do |(from, to), list|
        log.puts "     #{from.inspect} -> #{to}: #{list.size}"
        list.sort_by { |c| c[:email] }.each { |c| log.puts "         donor #{c[:donor].id} #{c[:email]}" }
      end

      log.puts
      log.puts "C. KIT: #{plan[:create_in_kit].size} donor(s) to ADD (subscribed here, missing in Kit)"
      plan[:create_in_kit].sort_by { |c| c[:email] }.each do |c|
        log.puts "     + #{c[:email]}  (donor #{c[:donor].id}, role #{c[:role]}, " \
                 "segment #{CATEGORY_TAG_NAMES[CATEGORY_TAGS[donor_category(c[:donor])]]})"
      end

      log.puts
      log.puts "D. KIT: #{plan[:field_updates].size} subscriber(s) with custom field changes (#{SYNCED_FIELDS.join(', ')})"
      changes = Hash.new { |h, k| h[k] = [] }
      plan[:field_updates].each do |u|
        u[:fields].each { |key, value| changes[[key, u[:from][key].to_s, value]] << u[:email] }
      end
      changes.sort_by { |_, emails| -emails.size }.each do |(key, from, to), emails|
        log.puts "     #{key}: #{from.present? ? from : '(empty)'} -> #{to}: #{emails.size}"
        emails.sort.each { |email| log.puts "         #{email}" }
      end

      log.puts
      log.puts "E. KIT: #{plan[:tag_moves].size} subscriber(s) to move between segments (category tags)"
      plan[:tag_moves].group_by { |m| [m[:remove].sort, m[:add].sort] }.sort_by { |_, l| -l.size }.each do |(remove, add), list|
        from = remove.empty? ? '(no category tag)' : tag.call(remove)
        to = add.empty? ? '(keeps its correct tag)' : tag.call(add)
        log.puts "     #{from} -> #{to}: #{list.size}"
        list.sort_by { |m| m[:email] }.each { |m| log.puts "         #{m[:email]}  (#{m[:reason]})" }
      end

      states = Hash.new(0)
      subscribers.each_value { |s| states[s['state']] += 1 }
      log.puts
      unless plan[:live_checked]
        log.puts "NOTE: many changes, so Kit changes were NOT confirmed live; a few may already be done (harmless)."
      end
      log.puts 'SUMMARY'
      log.puts "  Kit now:          #{subscribers.size} subscribers (#{states.sort.map { |s, n| "#{s} #{n}" }.join(', ')})"
      log.puts "  Kit API writes:   #{kit_writes(plan)} (#{plan[:create_in_kit].size} new subscribers, " \
               "#{plan[:field_updates].size} field updates, #{plan[:tag_moves].sum { |m| m[:add].size }} tags added, " \
               "#{plan[:tag_moves].sum { |m| m[:remove].size }} tags removed)"
      log.puts "  Database writes:  #{plan[:new_donors].size + plan[:status_changes].size}"
      log.puts "  #{KIT_ENDED_STATES.sum { |s| states[s] }} Kit subscribers can be deleted in the Kit UI (status Cancelled/Bounced/Complained)."
      log.puts '  Nothing else is changed: no other tags, no other custom fields.'
    end

    # Executes a plan from #plan. Returns the number of failed actions.
    def apply_plan(plan, log = $stdout)
      @failed = 0

      plan[:new_donors].each do |n|
        attempt(log, "new donor #{n[:email]} (#{n[:status]})") do
          create_donor_from_kit(n[:email], n[:first_name], n[:status]) unless Donor.find_by_any_email(n[:email]).exists?
        end
      end
      plan[:status_changes].each do |c|
        attempt(log, "donor #{c[:donor].id} #{c[:email]}: #{c[:from]} -> #{c[:to]}") { set_donor_status(c[:donor], c[:to]) }
      end
      plan[:create_in_kit].each do |c|
        attempt(log, "add to Kit #{c[:email]}") { create_in_kit(c[:email], c[:donor].first_name, c[:donor]) }
      end
      plan[:field_updates].each do |u|
        label = u[:fields].map { |key, value| "#{key} #{u[:from][key].presence || '(empty)'} -> #{value}" }.join(', ')
        attempt(log, "#{u[:email]}: #{label}") do
          client.update_subscriber(u[:subscriber_id], u[:kit_email], :fields => u[:fields])
        end
      end
      plan[:tag_moves].each do |m|
        label = "#{m[:email]}: #{m[:remove].map { |t| "-#{CATEGORY_TAG_NAMES[t]}" }.join(' ')} " \
                "#{m[:add].map { |t| "+#{CATEGORY_TAG_NAMES[t]}" }.join(' ')}".squeeze(' ')
        attempt(log, label) do
          # Add first, then remove: the subscriber is never without a segment.
          m[:add].each { |t| client.tag_subscriber(t, m[:subscriber_id]) }
          m[:remove].each { |t| client.remove_tag(t, m[:subscriber_id]) }
        end
      end

      @failed
    end

    private

    # Runs one action, logging the result. An error is reported and counted
    # but does not stop the run.
    def attempt(log, label)
      yield
      log.puts "  done   #{label}"
    rescue => e
      @failed += 1
      log.puts "  FAILED #{label}: #{e.message}"
    end

  end

end
