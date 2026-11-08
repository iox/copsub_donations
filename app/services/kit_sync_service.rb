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
# Every other tag (role/status tags from the October 2026 import, manual or
# automation tags) and all custom fields are left alone.
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
  # When donors share an email address, the "best" category wins.
  CATEGORY_PRIORITY = %w(current past newsletter)

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

    # Explicit newsletter opt-in (donation form checkbox). Adds the subscriber
    # to the newsletter form, so they enter its automation / welcome emails.
    # (The nightly sync gives them their category tag.)
    def subscribe_to_newsletter(email_address, first_name = nil)
      return if email_address.blank?
      client.upsert_subscriber(email_address.strip, :first_name => first_name)
      client.add_subscriber_to_form_by_email(KIT_NEWSLETTER_FORM_ID, email_address.strip)
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
    # Nightly sync. Step 1 (plan) only reads; step 2 (apply_plan) writes. The
    # dry run prints the plan and stops, so it shows exactly what a real run
    # would do.
    #
    #   subscribers:    KitClient#all_subscribers (downcased email => subscriber)
    #   category_tags:  KitClient#subscriber_ids_by_tag(CATEGORY_TAGS.values)
    # ------------------------------------------------------------------------
    def plan(donors, subscribers, category_tags)
      plan = { :new_donors => [], :status_changes => [], :unsubscribe => [],
               :tag_moves => [], :missing_in_kit => [] }

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
          plan[:missing_in_kit] << { :email => email, :donor_ids => group.map(&:id) }
        end
      end

      # C. Kit: exactly one category tag per (still) subscribed person.
      subscribers.each do |email, sub|
        next if KIT_ENDED_STATES.include?(sub['state']) || unsubscribing.include?(email)
        group = by_email[email] || [pulled_donor[email]].compact
        donor = group.min_by { |d| CATEGORY_PRIORITY.index(donor_category(d)) }
        desired = CATEGORY_TAGS[donor ? donor_category(donor) : 'newsletter']
        current = (category_tags[sub['id']] || Set.new).to_a
        add = current.include?(desired) ? [] : [desired]
        remove = current - [desired]
        next if add.empty? && remove.empty?
        plan[:tag_moves] << { :email => email, :subscriber_id => sub['id'], :add => add, :remove => remove,
                              :reason => category_reason(donor) }
      end

      plan
    end

    def kit_writes(plan)
      plan[:unsubscribe].size + plan[:tag_moves].sum { |m| m[:add].size + m[:remove].size }
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
      log.puts "E. NOT CHANGED, for information: #{plan[:missing_in_kit].size} donor(s) subscribed here but not in Kit."
      log.puts '     The sync never creates Kit subscribers; people join through the Kit or donation forms.'
      plan[:missing_in_kit].first(50).each { |m| log.puts "     ? #{m[:email]}  (donor #{m[:donor_ids].join(',')})" }
      log.puts "     ... and #{plan[:missing_in_kit].size - 50} more" if plan[:missing_in_kit].size > 50

      states = Hash.new(0)
      subscribers.each_value { |s| states[s['state']] += 1 }
      ended = KIT_ENDED_STATES.sum { |s| states[s] } + plan[:unsubscribe].size
      log.puts
      log.puts 'SUMMARY'
      log.puts "  Kit now:          #{subscribers.size} subscribers (#{states.sort.map { |s, n| "#{s} #{n}" }.join(', ')})"
      log.puts "  Kit API writes:   #{kit_writes(plan)} (#{plan[:unsubscribe].size} unsubscribes, " \
               "#{plan[:tag_moves].sum { |m| m[:add].size }} tags added, #{plan[:tag_moves].sum { |m| m[:remove].size }} tags removed)"
      log.puts "  Database writes:  #{plan[:new_donors].size + plan[:status_changes].size}"
      log.puts "  After this run, #{ended} Kit subscribers can be deleted in the Kit UI (status Cancelled/Bounced/Complained)."
      log.puts '  Nothing else is changed: no other tags, no custom fields, no new Kit subscribers.'
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
