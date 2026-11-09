# One-off cleanup (November 2026) that separates newsletter status from donor
# type and brings our database in line with Kit, so that from then on the
# nightly KitSyncService only has to keep them equal.
#
#   1. Merge donor rows that share an email address (donations, notes and role
#      history move to the surviving row; its blank fields are filled in).
#   2. role becomes the donor type only: 'inactive_subscriber' (and blank or
#      unknown roles) become 'subscriber' (never donated) or
#      'inactive_supporter' (donated before).
#   3. mailchimp_status becomes the newsletter status:
#      - in Kit: Kit's state, EXCEPT import-era subscribers (created in Kit
#        before KIT_IMPORT_CUTOFF) whom our data marks as unsubscribed (status
#        'unsubscribed' or role 'inactive_subscriber'): they stay unsubscribed
#        and are unsubscribed in Kit too.
#      - not in Kit: 'unsubscribed' with the same signals (this fixes the
#        ~1,900 donors wrongly marked 'subscribed' by a 2018 Mailchimp sync
#        bug), otherwise unchanged ('subscribed' ones are then added to Kit by
#        the nightly sync).
#
# Also provides a read-only audit (rake kit:audit).
class KitCleanup

  # Columns copied from merged rows into the surviving row when it has none.
  # (Donation statistics are recalculated instead.)
  FILL_FIELDS = %w(wordpress_id first_name last_name user_adress city country paypalid user_phone alternativeid
                   stripe_customer_id stripe_card_expiration_date custom_donation_interval selected_donor_type
                   selected_amount filled_donation_form_date stopped_regular_donations_date last_paypal_failure
                   last_paypal_failure_type old_notes_backup)

  VALID_ROLES = KitSyncService::ROLE_PRIORITY

  class << self

    def donated?(donor)
      donor.donated_total.to_i > 0 || donor.number_of_donations.to_i > 0
    end

    def fixed_role(donor)
      return donor.role if VALID_ROLES.include?(donor.role)
      donated?(donor) ? 'inactive_supporter' : 'subscriber'
    end

    def import_era?(subscriber)
      created_at = Time.parse(subscriber['created_at'].to_s) rescue nil
      created_at.present? && created_at < KitSyncService::KIT_IMPORT_CUTOFF
    end

    def unsubscribe_signal?(group)
      group.any? { |d| d.mailchimp_status == 'unsubscribed' || d.role == 'inactive_subscriber' }
    end

    def plan(donors, subscribers)
      plan = { :merges => [], :role_changes => [], :status_changes => [], :kit_unsubscribe => [] }

      by_email = donors.group_by { |d| d.user_email.to_s.strip.downcase }
      by_email.delete('')

      by_email.each do |email, group|
        # 1. Merge
        survivor = group.max_by { |d| [d.number_of_donations.to_i, d.donated_total.to_i, -d.id] }
        others = group - [survivor]
        if others.any?
          fills = {}
          FILL_FIELDS.each do |field|
            next if survivor.send(field).present?
            value = others.map { |d| d.send(field) }.find(&:present?)
            fills[field] = value if value.present?
          end
          plan[:merges] << { :email => email, :survivor => survivor, :others => others, :fills => fills }
        end

        # 2. Role (of the surviving row, considering the whole group)
        role = group.map { |d| fixed_role(d) }.min_by { |r| VALID_ROLES.index(r) }
        if survivor.role != role
          plan[:role_changes] << { :donor => survivor, :email => email, :from => survivor.role, :to => role }
        end

        # 3. Newsletter status
        sub = subscribers[email]
        if sub
          if %w(active inactive).include?(sub['state']) && import_era?(sub) && unsubscribe_signal?(group)
            status = 'unsubscribed'
            reason = 'unsubscribed here, active in Kit only because of the October import'
            plan[:kit_unsubscribe] << { :email => email, :subscriber_id => sub['id'], :kit_state => sub['state'] }
          else
            status = KitSyncService::STATE_TO_STATUS[sub['state'].to_s]
            reason = "Kit state: #{sub['state']}"
          end
        elsif unsubscribe_signal?(group)
          status = 'unsubscribed'
          reason = 'not in Kit, unsubscribed / inactive_subscriber here'
        elsif group.any? { |d| d.mailchimp_status == 'subscribed' }
          status = 'subscribed'
          reason = 'not in Kit, subscribed here (will be added to Kit by the nightly sync)'
        else
          status = KitSyncService::STATE_TO_STATUS.values.include?(survivor.mailchimp_status) ? survivor.mailchimp_status : 'not_present'
          reason = 'not in Kit'
        end
        if survivor.mailchimp_status != status
          plan[:status_changes] << { :donor => survivor, :email => email, :from => survivor.mailchimp_status,
                                     :to => status, :reason => reason }
        end
      end

      plan
    end

    def print_plan(plan, log = $stdout)
      log.puts
      log.puts "1. MERGE DUPLICATE DONORS: #{plan[:merges].size} email address(es)"
      plan[:merges].each do |m|
        s = m[:survivor]
        log.puts "     #{m[:email]}: keep donor #{s.id} (#{s.number_of_donations.to_i} donations), " \
                 "merge in #{m[:others].map { |d| "donor #{d.id} (#{d.number_of_donations.to_i} donations)" }.join(', ')}"
        log.puts "         fill in: #{m[:fills].map { |k, v| "#{k}=#{v.to_s[0, 40]}" }.join(', ')}" if m[:fills].any?
      end

      log.puts
      log.puts "2. ROLE (donor type only): #{plan[:role_changes].size} change(s)"
      plan[:role_changes].group_by { |c| [c[:from], c[:to]] }.sort_by { |_, l| -l.size }.each do |(from, to), list|
        log.puts "     #{from.inspect} -> #{to}: #{list.size}"
        list.sort_by { |c| c[:donor].id }.each { |c| log.puts "         donor #{c[:donor].id} #{c[:email]}" }
      end

      log.puts
      log.puts "3. NEWSLETTER STATUS (mailchimp_status): #{plan[:status_changes].size} change(s)"
      plan[:status_changes].group_by { |c| [c[:from], c[:to], c[:reason]] }.sort_by { |_, l| -l.size }.each do |(from, to, reason), list|
        log.puts "     #{from.inspect} -> #{to}  [#{reason}]: #{list.size}"
        list.sort_by { |c| c[:donor].id }.each { |c| log.puts "         donor #{c[:donor].id} #{c[:email]}" }
      end

      log.puts
      log.puts "4. KIT: #{plan[:kit_unsubscribe].size} subscriber(s) to UNSUBSCRIBE (import-era, unsubscribed here)"
      plan[:kit_unsubscribe].sort_by { |u| u[:email] }.each { |u| log.puts "     - #{u[:email]}  (Kit: #{u[:kit_state]})" }

      log.puts
      log.puts 'SUMMARY'
      log.puts "  Merges: #{plan[:merges].size}, role changes: #{plan[:role_changes].size}, " \
               "status changes: #{plan[:status_changes].size}, Kit unsubscribes: #{plan[:kit_unsubscribe].size}"
    end

    def apply_plan(plan, log = $stdout)
      failed = 0
      step = lambda do |label, &block|
        begin
          block.call
          log.puts "  done   #{label}"
        rescue => e
          failed += 1
          log.puts "  FAILED #{label}: #{e.class}: #{e.message}"
        end
      end

      plan[:merges].each do |m|
        step.call("merge #{m[:email]} into donor #{m[:survivor].id}") { merge(m) }
      end
      plan[:role_changes].each do |c|
        step.call("donor #{c[:donor].id} #{c[:email]}: role #{c[:from].inspect} -> #{c[:to]}") do
          donor = Donor.find(c[:donor].id)
          donor.role = c[:to] # records the RoleChange history
          donor.save!
        end
      end
      plan[:status_changes].each do |c|
        step.call("donor #{c[:donor].id} #{c[:email]}: status #{c[:from].inspect} -> #{c[:to]}") do
          donor = Donor.find(c[:donor].id)
          donor.mailchimp_status = c[:to] # direct setter: not attr_accessible
          donor.save!
        end
      end
      plan[:kit_unsubscribe].each do |u|
        step.call("Kit: unsubscribe #{u[:email]}") { KitSyncService.client.unsubscribe(u[:subscriber_id]) }
      end

      failed
    end

    def merge(m)
      survivor = Donor.find(m[:survivor].id)
      other_ids = m[:others].map(&:id)
      Donor.transaction do
        Donation.where(:donor_id => other_ids).update_all(:donor_id => survivor.id)
        Note.where(:donor_id => other_ids).update_all(:donor_id => survivor.id)
        RoleChange.where(:donor_id => other_ids).update_all(:donor_id => survivor.id)
        m[:fills].each { |field, value| survivor.send("#{field}=", value) }
        survivor.save!
        Note.create!(:donor_id => survivor.id,
                     :body => "#{Date.today}: merged duplicate donor(s) " +
                              m[:others].map { |d| "##{d.id} (paymentid #{d.paymentid.presence || '-'})" }.join(', ') +
                              " into this donor (same email address).")
        Donor.where(:id => other_ids).delete_all
      end
      # Recalculate totals, dates and donation method from the merged donations
      survivor.reload.update_amount_donated_last_year!
    end

    # Read-only health check: data problems plus everything the nightly sync
    # would still change (quick snapshot comparison, no live checks).
    def audit(donors, subscribers, category_tags, log = $stdout)
      problems = 0

      dups = donors.group_by { |d| d.user_email.to_s.strip.downcase }.reject { |e, g| e.blank? || g.size < 2 }
      bad_roles = donors.reject { |d| VALID_ROLES.include?(d.role) }
      bad_status = donors.reject { |d| Donor::NEWSLETTER_STATUSES.include?(d.mailchimp_status) }

      log.puts
      log.puts 'DATA'
      log.puts "  donors: #{donors.size}"
      log.puts "  roles:  #{donors.group_by(&:role).map { |r, l| "#{r.inspect} #{l.size}" }.sort.join(', ')}"
      log.puts "  newsletter status: #{donors.group_by(&:mailchimp_status).map { |s, l| "#{s.inspect} #{l.size}" }.sort.join(', ')}"
      [['duplicate email addresses', dups.keys],
       ['donors with a role that is not a donor type', bad_roles.map { |d| "donor #{d.id} #{d.role.inspect}" }],
       ['donors with an unknown newsletter status', bad_status.map { |d| "donor #{d.id} #{d.mailchimp_status.inspect}" }]].each do |label, list|
        problems += list.size
        log.puts "  #{list.empty? ? 'OK  ' : 'FIX '} #{label}: #{list.size}#{"  e.g. #{list.first(5).join('; ')}" if list.any?}"
      end

      plan = KitSyncService.plan(donors, subscribers, category_tags, :live_check => false)
      log.puts
      log.puts 'SYNC WITH KIT (what the nightly sync would still change)'
      { :new_donors => 'in Kit, unknown here',
        :status_changes => 'newsletter status differs from Kit',
        :create_in_kit => 'subscribed here, missing in Kit',
        :field_updates => 'Kit custom fields (role, mailchimp_status) differ',
        :tag_moves => 'Kit segment tag wrong' }.each do |key, label|
        list = plan[key]
        problems += list.size
        log.puts "  #{list.empty? ? 'OK  ' : 'DIFF'} #{label}: #{list.size}#{"  e.g. #{list.first(5).map { |x| x[:email] }.join('; ')}" if list.any?}"
      end

      log.puts
      log.puts problems.zero? ? 'RESULT: 100% in sync.' : "RESULT: #{problems} difference(s)."
      problems
    end

  end

end
