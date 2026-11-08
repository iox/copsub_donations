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
    def apply_subscriber_state(email_address, kit_state, first_name = nil)
      status = STATE_TO_STATUS[kit_state.to_s]
      return nil if status.nil? || email_address.blank?

      donor = Donor.find_by_any_email(email_address).first

      if donor.nil?
        # Mirror the old Mailchimp sync: only create donors for confirmed subscribers.
        return nil unless status == 'subscribed'
        donor = Donor.new(
          :user_email => email_address.strip,
          :role => 'subscriber',
          :mailchimp_status => status,
          :donated_last_year_in_dkk => 0
        )
        donor.first_name = first_name if first_name.present?
        donor.save
        return donor
      end

      attrs = {}
      attrs[:mailchimp_status] = status if donor.mailchimp_status != status
      if status == 'subscribed' && (donor.role.blank? || donor.role == 'inactive_subscriber')
        attrs[:role] = 'subscriber'
      elsif status == 'unsubscribed' && donor.role == 'subscriber'
        attrs[:role] = 'inactive_subscriber'
      end

      donor.update_attributes(attrs) if attrs.present?
      donor
    end

    # Pushes one donor to Kit: subscriber record, custom fields and tags.
    #
    # Consent rule: only donors who opted into the newsletter in our app
    # (mailchimp_status 'subscribed') are ever CREATED in Kit. Everyone else is
    # only updated if they already exist there as an active subscriber (e.g.
    # they subscribed through the website form). Donors who never opted in must
    # never become Kit subscribers, or they would start receiving emails.
    def push_donor(donor)
      return nil if donor.user_email.blank?
      email = donor.user_email.strip

      subscriber =
        if donor.mailchimp_status == 'subscribed'
          client.upsert_subscriber(email, :first_name => donor.first_name)
        else
          # Do not create; only enrich existing active subscribers.
          client.subscriber(email)
        end
      return nil if subscriber.nil?

      client.update_subscriber(subscriber['id'], email,
        :first_name => donor.first_name,
        :fields => custom_fields_for(donor))

      current_tag_ids = client.tags_for_subscriber(subscriber['id']).map { |t| t['id'] }
      desired_tag_ids = desired_tags_for(donor)

      (desired_tag_ids - current_tag_ids).each { |tag_id| client.add_tag(tag_id, email) }
      ((current_tag_ids & MANAGED_TAG_IDS) - desired_tag_ids).each { |tag_id| client.remove_tag(tag_id, subscriber['id']) }

      subscriber
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

    # Cheap local fingerprint of everything we push to Kit. The nightly sync
    # task stores these per donor and only calls the API for donors whose
    # fingerprint changed since the last run (avoids re-pushing 10k donors
    # every night, since the daily donor update touches all updated_at values).
    def fingerprint(donor)
      [
        donor.user_email.to_s.strip,
        donor.first_name, donor.last_name, donor.role, donor.mailchimp_status,
        donor_category(donor), donor.donated_total.to_i > 0,
        donor.number_of_donations.to_i, donor.donation_method,
        donor.city, donor.country
      ].join('|')
    end

  end

end
