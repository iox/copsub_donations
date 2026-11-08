# Keeps the donor list (this app) and Kit.com (our newsletter tool) in sync.
#
# The tag and custom field conventions below are the ones used when the donor
# list was imported into Kit (October 2026), so both systems stay consistent:
#
#   Role tags:     subscriber, inactive_subscriber, recurring_donor,
#                  single_donor, inactive_donor
#   Status tags:   active (= subscribed), unsubscribed, unknown-status (= never subscribed)
#   Category tags: currently_donating (donated in the last 92 days), past_donor,
#                  newsletter_subscriber
#   donor tag:     everyone who has donated at least once
#
#   Custom fields: role, mailchimp_status, donor_category, number_of_donations,
#                  donation_method, city, country, last_name, donor_id
#
# Only tags in MANAGED_TAG_IDS are ever added or removed by this app; tags
# applied by Kit automations or manually are never touched.
class KitSyncService

  # Tag IDs (Kit dashboard -> Audience -> Manage tags)
  ROLE_TAGS = {
    'subscriber'          => 24193626,
    'inactive_subscriber' => 24193628,
    'recurring_supporter' => 24193625, # tag name: recurring_donor
    'single_supporter'    => 24193630, # tag name: single_donor
    'inactive_supporter'  => 24193624, # tag name: inactive_donor
  }

  STATUS_TAGS = {
    'subscribed'   => 24193627, # tag name: active
    'unsubscribed' => 24733356, # tag name: unsubscribed
    'not_present'  => 24733360, # tag name: unknown-status
  }

  CATEGORY_TAGS = {
    'current'    => 24733359, # tag name: currently_donating
    'past'       => 24733350, # tag name: past_donor
    'newsletter' => 24733357, # tag name: newsletter_subscriber
  }

  DONOR_TAG_ID = 24193629 # tag name: donor

  MANAGED_TAG_IDS = (ROLE_TAGS.values + STATUS_TAGS.values + CATEGORY_TAGS.values + [DONOR_TAG_ID]).uniq

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

  # Kit states in which a subscriber no longer receives emails. We never
  # reactivate these through the API: a genuine opt-in must come from a form.
  KIT_ENDED_STATES = %w(cancelled bounced complained)

  class << self

    def client
      @client ||= KitClient.new
    end

    # Explicit newsletter opt-in (donation form checkbox). Adds the subscriber
    # to the newsletter form, so they enter its automation / welcome emails.
    def subscribe_to_newsletter(email_address, first_name = nil)
      return if email_address.blank?
      client.upsert_subscriber(email_address.strip, :first_name => first_name)
      client.add_subscriber_to_form_by_email(KIT_NEWSLETTER_FORM_ID, email_address.strip)
    end

    # Applies a Kit subscriber's state to our donor list. Used by the Kit
    # webhooks (real time) and by the nightly sync task. Returns the affected
    # donor, or nil when nothing matched / nothing needed changing.
    #
    # authoritative: webhooks are real events and always apply. The nightly
    # bulk pull passes false for subscribers from the October 2026 import (see
    # kit_state_authoritative?), whose 'active' state may be stale: then an
    # app 'unsubscribed' is never flipped back to 'subscribed', and a pending
    # ('inactive') Kit state never overwrites a known app status.
    def apply_subscriber_state(email_address, kit_state, first_name = nil, authoritative = true)
      status = STATE_TO_STATUS[kit_state.to_s]
      return nil if status.nil? || email_address.blank?

      donor = Donor.find_by_any_email(email_address).first

      if donor.nil?
        # Mirror the old Mailchimp sync: only create donors for confirmed subscribers.
        return nil unless status == 'subscribed'
        donor = Donor.new(
          :user_email => email_address.strip,
          :role => 'subscriber'
        )
        # mailchimp_status / donated_last_year_in_dkk are NOT attr_accessible,
        # so they must be assigned with direct setters (mass assignment would
        # silently drop them).
        donor.mailchimp_status = status
        donor.donated_last_year_in_dkk = 0
        donor.first_name = first_name if first_name.present?
        donor.save
        return donor
      end

      unless authoritative
        return nil if status == 'subscribed' && donor.mailchimp_status == 'unsubscribed'
        return nil if status == 'not_present' && donor.mailchimp_status.present?
      end

      changed = false
      if donor.mailchimp_status != status
        # Direct setter: mailchimp_status is not attr_accessible.
        donor.mailchimp_status = status
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
      changed ? donor : nil
    end

    # Whether a Kit subscriber's state can be trusted by the bulk pull.
    def kit_state_authoritative?(subscriber)
      created_at = Time.parse(subscriber['created_at'].to_s) rescue nil
      created_at.present? && created_at >= KIT_IMPORT_CUTOFF
    end

    # Diff-based push of our donors to Kit. Works from two bulk snapshots taken
    # up front, so API calls are only made for real differences:
    #
    #   subscribers:    KitClient#all_subscribers (downcased email => subscriber)
    #   tag_membership: KitClient#subscriber_ids_by_tag(MANAGED_TAG_IDS)
    #
    # Per email address (donors sharing an address are handled together; if
    # any of them unsubscribed, the address counts as unsubscribed):
    #
    #   app unsubscribed, Kit active/pending   -> update tags/fields, unsubscribe
    #   app subscribed, not in Kit             -> create, set fields and tags
    #   app subscribed, Kit cancelled/bounced  -> skip (never reactivate via API)
    #   in Kit as active/pending               -> update fields/tags on diff only
    #   app not subscribed, not in Kit         -> skip (no consent: never create)
    #
    # Returns a Hash of counters. Errors on one address are reported and counted
    # but do not stop the run.
    def reconcile(donors, subscribers:, tag_membership:, log: $stdout)
      stats = Hash.new(0)

      groups = donors.group_by { |d| d.user_email.to_s.strip.downcase }
      groups.delete('')

      groups.each_with_index do |(email, group), index|
        begin
          donor = representative_donor(group)
          stats[reconcile_one(email, donor, subscribers[email], tag_membership)] += 1
        rescue => e
          stats[:failed] += 1
          log.puts "  ! #{email} (donor #{group.map(&:id).join(',')}): #{e.message}"
        end
        log.puts "  ... #{index + 1}/#{groups.size} addresses checked" if ((index + 1) % 1000).zero?
      end

      stats
    end

    # The donor whose data represents a shared email address: an unsubscribed
    # one if any (unsubscribing wins), otherwise the biggest donor.
    def representative_donor(group)
      candidates = group.select { |d| d.mailchimp_status == 'unsubscribed' }
      candidates = group if candidates.empty?
      candidates.max_by { |d| [d.donated_total.to_i, d.number_of_donations.to_i, -d.id] }
    end

    # Returns a Symbol describing what happened (used as a stats key).
    def reconcile_one(email, donor, subscriber, tag_membership)
      status = donor.mailchimp_status

      if subscriber.nil?
        return :skipped_no_consent unless status == 'subscribed'
        subscriber = client.upsert_subscriber(donor.user_email.strip, :first_name => donor.first_name)
        enrich(donor, subscriber, Set.new)
        return :created
      end

      return :skipped_ended_in_kit if KIT_ENDED_STATES.include?(subscriber['state'])

      current_tags = tag_membership[subscriber['id']] || Set.new
      changed = enrich(donor, subscriber, current_tags)

      if status == 'unsubscribed'
        client.unsubscribe(subscriber['id'])
        return :unsubscribed
      end

      changed ? :updated : :unchanged
    end

    # Brings a Kit subscriber's first name, custom fields and managed tags in
    # line with the donor, calling the API only for actual differences.
    # Returns true if anything was changed.
    def enrich(donor, subscriber, current_tags)
      changed = false

      current_fields = subscriber['fields'] || {}
      field_diff = custom_fields_for(donor).reject { |key, value| current_fields[key].to_s == value.to_s }
      name_diff = donor.first_name.present? && subscriber['first_name'].to_s != donor.first_name.to_s

      if field_diff.any? || name_diff
        # Keep Kit's own email address (casing etc.); we matched it case-insensitively.
        client.update_subscriber(subscriber['id'], subscriber['email_address'],
          :first_name => (donor.first_name if name_diff),
          :fields => field_diff)
        changed = true
      end

      desired = desired_tags_for(donor)
      current = current_tags.to_a & MANAGED_TAG_IDS
      (desired - current).each { |tag_id| client.tag_subscriber(tag_id, subscriber['id']); changed = true }
      (current - desired).each { |tag_id| client.remove_tag(tag_id, subscriber['id']); changed = true }

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

    def desired_tags_for(donor)
      tags = []
      tags << ROLE_TAGS[donor.role] if ROLE_TAGS[donor.role]
      tags << STATUS_TAGS[donor.mailchimp_status] if STATUS_TAGS[donor.mailchimp_status]
      tags << CATEGORY_TAGS[donor_category(donor)]
      tags << DONOR_TAG_ID if donor.donated_total.to_i > 0
      tags.compact.uniq
    end

    # Values for the custom fields that already exist in the Kit account.
    def custom_fields_for(donor)
      fields = {
        'role' => donor.role,
        'mailchimp_status' => donor.mailchimp_status,
        'donor_category' => donor_category(donor),
        'number_of_donations' => donor.number_of_donations.to_s,
        'donation_method' => donor.donation_method,
        'city' => donor.city,
        'country' => donor.country,
        'last_name' => donor.last_name,
        'donor_id' => donor.id.to_s,
      }
      fields.reject { |_, value| value.blank? }
    end

  end

end
