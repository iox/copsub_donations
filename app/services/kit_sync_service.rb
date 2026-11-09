# Keeps the donor list (this app) and Kit.com (our newsletter tool) in sync.
#
# What matters in Kit (and the ONLY things this app changes there):
#
#  1. Kit only holds people who want the newsletter. Donors who unsubscribed
#     here are unsubscribed in Kit too. (The API cannot delete subscribers; they
#     are removed periodically in the Kit UI by filtering on status Cancelled /
#     Bounced / Complained. The plan has a 10,000 subscriber limit.)
#
#  2. The three segments configured in Kit, each based on one category tag.
#     Every subscriber carries exactly one of them:
#
#       Segment "Currently donating (past 3 months)"   -> tag currently_donating
#       Segment "Past donors (donated more than 3 ...)" -> tag past_donor
#       Segment "Never donated (just subscribed)"      -> tag newsletter_subscriber
#
#     The category follows from our donation data (see donor_category) and
#     changes over time, so the nightly sync moves people between them.
#
#  3. The 'role' custom field (recurring_supporter, single_supporter,
#     inactive_supporter, subscriber, inactive_subscriber), so Kit can tell
#     recurring donors from one-time donors.
#
#  4. Donors who tick the newsletter box on the donation form are added to Kit
#     at once (and retried nightly if that failed). Nobody else is ever added.
#
# Every other tag (role/status tags from the October 2026 import, manual or
# automation tags) and every other custom field is left alone.
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
  ROLE_PRIORITY = %w(recurring_supporter single_supporter inactive_supporter subscriber inactive_subscriber)

  # Kit subscriber state => our donors.mailchimp_status values
  STATE_TO_STATUS = {
    'active'     => 'subscribed',
    'cancelled'  => 'unsubscribed',
    'bounced'    => 'unsubscribed',
    'complained' => 'unsubscribed',
    'inactive'   => 'not_present',
  }

  # Kit subscribers created before this moment come from the October 2026
  # bulk import, which marked ~everyone (including people who had unsubscribed
  # in Mailchimp) as active. Their Kit state is therefore NOT trusted to flip a
  # donor back to 'subscribed'. Subscribers created afterwards signed up for
  # real (website form / donation form, double opt-in), so their state is.
  KIT_IMPORT_CUTOFF = Time.utc(2026, 10, 17)

  # Kit states in which a subscriber no longer receives emails.
  KIT_ENDED_STATES = %w(cancelled bounced complained)

  class << self

    def client
      @client ||= KitClient.new
    end

    # Explicit newsletter opt-in (donation form checkbox): creates the Kit
    # subscriber right away and puts them in their segment (category tag), so
    # they get the very next newsletter. If this fails, the nightly sync
    # retries it (see "create_in_kit" in #plan).
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

    # Creates (or updates) a Kit subscriber and gives them their category tag.
    # Only for people who opted in.
    def create_in_kit(email_address, first_name, donor)
      subscriber = client.upsert_subscriber(email_address.strip, :first_name => first_name)
      category = donor ? donor_category(donor) : 'newsletter'
      client.tag_subscriber(CATEGORY_TAGS[category], subscriber['id'])
      if donor && donor.role.present?
        client.update_subscriber(subscriber['id'], subscriber['email_address'] || email_address.strip,
                                 :fields => { 'role' => donor.role })
      end
      subscriber
    end

    # Applies a Kit subscriber's state to our donor list (real-time webhooks).
    # Returns the affected donor, or nil when nothing matched / changed.
    def apply_subscriber_state(email_address, kit_state, first_name = nil, authoritative = true)
      status = STATE_TO_STATUS[kit_state.to_s]
      return nil if status.nil? || email_address.blank?

      donor = Donor.find_by_any_email(email_address).first
      if donor.nil?
        # Only create donors for confirmed subscribers.
        return nil unless status == 'subscribed'
        return create_subscriber_donor(email_address, first_name)
      end

      return nil unless status_change_allowed?(donor, status, authoritative)
      set_donor_status(donor, status) ? donor : nil
    end

    # authoritative: webhooks are real events and always apply. The nightly
    # bulk pull treats subscribers from the October 2026 import as not
    # authoritative: their 'active' state may be stale, so it never flips an
    # app 'unsubscribed' back to 'subscribed', and a pending ('inactive') Kit
    # state never overwrites a known app status.
    def status_change_allowed?(donor, status, authoritative)
      return true if authoritative
      return false if status == 'subscribed' && donor.mailchimp_status == 'unsubscribed'
      return false if status == 'not_present' && donor.mailchimp_status.present?
      true
    end

    def kit_state_authoritative?(subscriber)
      created_at = Time.parse(subscriber['created_at'].to_s) rescue nil
      created_at.present? && created_at >= KIT_IMPORT_CUTOFF
    end

    def create_subscriber_donor(email_address, first_name)
      donor = Donor.new(:user_email => email_address.strip, :role => 'subscriber')
      # mailchimp_status / donated_last_year_in_dkk are NOT attr_accessible,
      # so they must be assigned with direct setters (mass assignment would
      # silently drop them).
      donor.mailchimp_status = 'subscribed'
      donor.donated_last_year_in_dkk = 0
      donor.first_name = first_name if first_name.present?
      donor.save
      donor
    end

    # Sets the newsletter status (and the matching subscriber role). Returns
    # true if anything changed.
    def set_donor_status(donor, status)
      changed = false
      if donor.mailchimp_status != status
        donor.mailchimp_status = status # direct setter: not attr_accessible
        changed = true
      end
      if status == 'subscribed' && (donor.role.blank? || donor.role == 'inactive_subscriber')
        donor.role = 'subscriber'
        changed = true
      elsif status == 'unsubscribed' && donor.role == 'subscriber'
        donor.role = 'inactive_subscriber'
        changed = true
      end
      donor.save if changed
      changed
    end

    # The donor's role once a planned status change is applied (same rules as
    # set_donor_status).
    def role_after(donor, new_status)
      return 'subscriber' if new_status == 'subscribed' && (donor.role.blank? || donor.role == 'inactive_subscriber')
      return 'inactive_subscriber' if new_status == 'unsubscribed' && donor.role == 'subscriber'
      donor.role
    end

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

    # ------------------------------------------------------------------------
    # Nightly sync. Step 1 (plan) only reads (Kit snapshots, plus a live tag
    # check for each candidate segment move); step 2 (apply_plan) writes. The
    # dry run prints the plan and stops, so it shows exactly what a real run
    # would do.
    #
    #   subscribers:    KitClient#all_subscribers (downcased email => subscriber)
    #   category_tags:  KitClient#subscriber_ids_by_tag(CATEGORY_TAGS.values)
    # ------------------------------------------------------------------------
    def plan(donors, subscribers, category_tags)
      plan = { :new_donors => [], :status_changes => [], :unsubscribe => [],
               :tag_moves => [], :role_updates => [], :create_in_kit => [], :missing_in_kit => [] }

      by_email = donors.group_by { |d| d.user_email.to_s.strip.downcase }
      by_email.delete('')

      # A. Our database: subscription states from Kit.
      new_status = {}   # donor id => status after this run
      pulled_donor = {} # Kit email => donor matched by any of its email fields
      subscribers.each do |email, sub|
        status = STATE_TO_STATUS[sub['state'].to_s]
        next if status.nil?
        donor = by_email[email] ? by_email[email].first : Donor.find_by_any_email(email).first
        if donor.nil?
          plan[:new_donors] << { :email => email, :kit_created_at => sub['created_at'] } if status == 'subscribed'
          next
        end
        pulled_donor[email] = donor
        next if donor.mailchimp_status == status
        next unless status_change_allowed?(donor, status, kit_state_authoritative?(sub))
        next if new_status.key?(donor.id)
        new_status[donor.id] = status
        plan[:status_changes] << { :donor => donor, :email => email, :from => donor.mailchimp_status,
                                   :to => status, :kit_state => sub['state'] }
      end

      # B. Kit: unsubscribe people who are unsubscribed here.
      unsubscribing = Set.new
      by_email.each do |email, group|
        statuses = group.map { |d| new_status[d.id] || d.mailchimp_status }
        sub = subscribers[email]
        if statuses.include?('unsubscribed')
          next if sub.nil? || KIT_ENDED_STATES.include?(sub['state'])
          unsubscribing << email
          plan[:unsubscribe] << { :email => email, :subscriber_id => sub['id'], :kit_state => sub['state'],
                                  :kit_created_at => sub['created_at'], :donor_ids => group.map(&:id) }
        elsif statuses.include?('subscribed') && sub.nil?
          # Opted in on the donation form since Kit went live, but the
          # real-time subscription failed: retry it. Older 'subscribed' donors
          # missing in Kit are only reported (they were not in the import or
          # were deleted from Kit on purpose).
          opted_in = group.select do |d|
            d.mailchimp_status == 'subscribed' && d.filled_donation_form_date.present? &&
              d.filled_donation_form_date >= KIT_IMPORT_CUTOFF.to_date
          end
          if opted_in.any?
            donor = opted_in.min_by { |d| CATEGORY_PRIORITY.index(donor_category(d)) }
            plan[:create_in_kit] << { :email => email, :donor => donor, :form_date => opted_in.map(&:filled_donation_form_date).max }
          else
            plan[:missing_in_kit] << { :email => email, :donor_ids => group.map(&:id) }
          end
        end
      end

      # C. Kit: exactly one category tag per (still) subscribed person.
      subscribers.each do |email, sub|
        next if KIT_ENDED_STATES.include?(sub['state']) || unsubscribing.include?(email)
        group = by_email[email] || [pulled_donor[email]].compact
        donor = group.min_by { |d| CATEGORY_PRIORITY.index(donor_category(d)) }
        desired = CATEGORY_TAGS[donor ? donor_category(donor) : 'newsletter']
        current = (category_tags[sub['id']] || Set.new).to_a
        next if current == [desired]
        # Kit's per-tag listings lag behind by minutes, so confirm with the
        # subscriber's live tags (only for the few candidates) before planning.
        current = client.tags_for_subscriber(sub['id']).map { |t| t['id'] } & CATEGORY_TAGS.values
        add = current.include?(desired) ? [] : [desired]
        remove = current - [desired]
        next if add.empty? && remove.empty?
        plan[:tag_moves] << { :email => email, :subscriber_id => sub['id'], :add => add, :remove => remove,
                              :reason => category_reason(donor) }
      end

      # D. Kit: the 'role' custom field.
      subscribers.each do |email, sub|
        next if KIT_ENDED_STATES.include?(sub['state']) || unsubscribing.include?(email)
        roles = (by_email[email] || [pulled_donor[email]].compact).map { |d| [d, role_after(d, new_status[d.id])] }
        roles = roles.select { |_, role| role.present? }
        next if roles.empty?
        group = roles.map(&:first)
        desired = roles.map(&:last).min_by { |role| ROLE_PRIORITY.index(role) || ROLE_PRIORITY.size }
        next if (sub['fields'] || {})['role'].to_s == desired
        # Confirm with the live subscriber (listings can lag behind).
        live = client.subscriber_by_id(sub['id']) || {}
        current = (live['fields'] || {})['role'].to_s
        next if current == desired
        plan[:role_updates] << { :email => email, :subscriber_id => sub['id'], :kit_email => sub['email_address'],
                                 :from => current, :to => desired, :donor_ids => group.map(&:id) }
      end

      plan
    end

    def kit_writes(plan)
      plan[:unsubscribe].size + plan[:tag_moves].sum { |m| m[:add].size + m[:remove].size } +
        plan[:role_updates].size + plan[:create_in_kit].size * 3
    end

    def print_plan(plan, subscribers, log = $stdout)
      tag = ->(ids) { ids.map { |id| CATEGORY_TAG_NAMES[id] }.join(', ') }

      log.puts
      log.puts "A. OUR DATABASE: #{plan[:new_donors].size} new donor record(s) (subscribed in Kit, unknown here)"
      plan[:new_donors].each { |n| log.puts "     + #{n[:email]}  (in Kit since #{n[:kit_created_at]})" }

      log.puts
      log.puts "B. OUR DATABASE: #{plan[:status_changes].size} newsletter status change(s), following Kit"
      plan[:status_changes].each do |c|
        log.puts "     donor #{c[:donor].id} #{c[:email]}: #{c[:from].inspect} -> #{c[:to]}  (Kit state: #{c[:kit_state]})"
      end

      log.puts
      log.puts "C. KIT: #{plan[:unsubscribe].size} subscriber(s) to UNSUBSCRIBE (unsubscribed here, still active/pending in Kit)"
      plan[:unsubscribe].sort_by { |u| u[:email] }.each do |u|
        log.puts "     - #{u[:email]}  (Kit: #{u[:kit_state]}, in Kit since #{u[:kit_created_at].to_s[0, 10]}; donor #{u[:donor_ids].join(',')})"
      end

      log.puts
      log.puts "D. KIT: #{plan[:tag_moves].size} subscriber(s) to move between segments (category tags)"
      moves = plan[:tag_moves].group_by { |m| [m[:remove].sort, m[:add].sort] }
      moves.sort_by { |_, list| -list.size }.each do |(remove, add), list|
        from = remove.empty? ? '(no category tag)' : tag.call(remove)
        to = add.empty? ? '(keeps its correct tag)' : tag.call(add)
        log.puts "     #{from} -> #{to}: #{list.size}"
        list.sort_by { |m| m[:email] }.each { |m| log.puts "         #{m[:email]}  (#{m[:reason]})" }
      end

      log.puts
      log.puts "E. KIT: #{plan[:role_updates].size} subscriber(s) whose 'role' field changes"
      plan[:role_updates].group_by { |r| [r[:from], r[:to]] }.sort_by { |_, list| -list.size }.each do |(from, to), list|
        log.puts "     #{from.present? ? from : '(empty)'} -> #{to}: #{list.size}"
        list.sort_by { |r| r[:email] }.each { |r| log.puts "         #{r[:email]}  (donor #{r[:donor_ids].join(',')})" }
      end

      log.puts
      log.puts "F. KIT: #{plan[:create_in_kit].size} donor(s) to ADD (opted in on the donation form, but not in Kit yet)"
      plan[:create_in_kit].sort_by { |c| c[:email] }.each do |c|
        log.puts "     + #{c[:email]}  (donor #{c[:donor].id}, opted in #{c[:form_date]}, segment #{CATEGORY_TAG_NAMES[CATEGORY_TAGS[donor_category(c[:donor])]]})"
      end

      log.puts
      log.puts "G. NOT CHANGED, for information: #{plan[:missing_in_kit].size} older donor(s) marked subscribed here but not in Kit."
      log.puts '     Not added: no recent opt-in on record.'
      plan[:missing_in_kit].first(50).each { |m| log.puts "     ? #{m[:email]}  (donor #{m[:donor_ids].join(',')})" }
      log.puts "     ... and #{plan[:missing_in_kit].size - 50} more" if plan[:missing_in_kit].size > 50

      states = Hash.new(0)
      subscribers.each_value { |s| states[s['state']] += 1 }
      ended = KIT_ENDED_STATES.sum { |s| states[s] } + plan[:unsubscribe].size
      log.puts
      log.puts 'SUMMARY'
      log.puts "  Kit now:          #{subscribers.size} subscribers (#{states.sort.map { |s, n| "#{s} #{n}" }.join(', ')})"
      log.puts "  Kit API writes:   #{kit_writes(plan)} (#{plan[:create_in_kit].size} new subscribers, #{plan[:unsubscribe].size} unsubscribes, " \
               "#{plan[:tag_moves].sum { |m| m[:add].size }} tags added, #{plan[:tag_moves].sum { |m| m[:remove].size }} tags removed, " \
               "#{plan[:role_updates].size} role fields)"
      log.puts "  Database writes:  #{plan[:new_donors].size + plan[:status_changes].size}"
      log.puts "  After this run, #{ended} Kit subscribers can be deleted in the Kit UI (status Cancelled/Bounced/Complained)."
      log.puts '  Nothing else is changed: no other tags, no other custom fields.'
    end

    # Executes a plan from #plan. Returns the number of failed actions.
    def apply_plan(plan, log = $stdout)
      @failed = 0

      plan[:new_donors].each do |n|
        attempt(log, "new donor #{n[:email]}") { create_subscriber_donor(n[:email], nil) unless Donor.find_by_any_email(n[:email]).exists? }
      end
      plan[:status_changes].each do |c|
        attempt(log, "donor #{c[:donor].id} #{c[:email]} -> #{c[:to]}") { set_donor_status(c[:donor], c[:to]) }
      end
      plan[:unsubscribe].each do |u|
        attempt(log, "unsubscribe #{u[:email]}") { client.unsubscribe(u[:subscriber_id]) }
      end
      plan[:create_in_kit].each do |c|
        attempt(log, "add to Kit #{c[:email]}") { create_in_kit(c[:email], c[:donor].first_name, c[:donor]) }
      end
      plan[:role_updates].each do |r|
        attempt(log, "#{r[:email]}: role #{r[:from].present? ? r[:from] : '(empty)'} -> #{r[:to]}") do
          client.update_subscriber(r[:subscriber_id], r[:kit_email], :fields => { 'role' => r[:to] })
        end
      end
      plan[:tag_moves].each do |m|
        label = "#{m[:email]}: #{m[:remove].map { |t| "-#{CATEGORY_TAG_NAMES[t]}" }.join(' ')} #{m[:add].map { |t| "+#{CATEGORY_TAG_NAMES[t]}" }.join(' ')}".squeeze(' ')
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
