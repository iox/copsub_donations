# Nightly synchronization between our donor list and Kit.com (newsletter).
#
#   rake sync_kit_status            # pull states from Kit, then push differences
#   rake sync_kit_status DRY_RUN=1  # only report what the pull would change
#
# Real-time subscription/unsubscription events arrive through the Kit webhooks
# (KitWebhooksController). This task reconciles everything else and is
# diff-based: it reads all Kit subscribers and the members of our managed tags
# once (a few dozen API calls), compares with the database locally, and only
# calls the API for actual differences. See KitSyncService.reconcile.
#
# Run it under flock (cron does) so two runs never overlap:
#   flock -n tmp/kit_sync.lock -c 'RAILS_ENV=production bundle exec rake sync_kit_status'
desc 'Synchronize donors with Kit.com (pull subscriber states, push differences)'
task :sync_kit_status => :environment do
  dry_run = %w(true 1 yes).include?(ENV['DRY_RUN'].to_s.downcase)
  client = KitSyncService.client
  started = Time.now

  # --- 1. Snapshot of Kit ----------------------------------------------------
  puts "#{Time.now}: reading all Kit subscribers..."
  subscribers = client.all_subscribers
  puts "  #{subscribers.size} subscriber(s) in Kit."

  puts "#{Time.now}: reading managed tag memberships..."
  tag_membership = client.subscriber_ids_by_tag(KitSyncService::MANAGED_TAG_IDS)
  puts "  #{tag_membership.size} subscriber(s) carry managed tags."

  # --- 2. PULL: Kit states -> donors -----------------------------------------
  # Subscribers from the October 2026 import are not authoritative: their
  # 'active' state may be stale, so they never re-subscribe an unsubscribed donor.
  puts "#{Time.now}: PULL#{' (dry run)' if dry_run}..."
  pulled = 0
  subscribers.each_value do |subscriber|
    authoritative = KitSyncService.kit_state_authoritative?(subscriber)
    if dry_run
      status = KitSyncService::STATE_TO_STATUS[subscriber['state'].to_s]
      donor = Donor.find_by_any_email(subscriber['email_address'].to_s).first
      next if donor.nil? || status.nil? || donor.mailchimp_status == status
      next if !authoritative && status == 'subscribed' && donor.mailchimp_status == 'unsubscribed'
      next if !authoritative && status == 'not_present' && donor.mailchimp_status.present?
      puts "  would set donor #{donor.id} (#{subscriber['email_address']}): #{donor.mailchimp_status.inspect} -> #{status}"
      pulled += 1
    else
      donor = KitSyncService.apply_subscriber_state(subscriber['email_address'], subscriber['state'],
                                                    subscriber['first_name'], authoritative)
      pulled += 1 if donor
    end
  end
  puts "  #{pulled} donor(s) #{'would be ' if dry_run}created/updated from Kit states."

  if dry_run
    puts 'Dry run: skipping the push.'
    next
  end

  # --- 3. PUSH: differences -> Kit -------------------------------------------
  puts "#{Time.now}: PUSH (reconcile)..."
  donors = Donor.where("user_email IS NOT NULL AND user_email != '' AND user_email LIKE '%@%'").order(:id).to_a
  stats = KitSyncService.reconcile(donors, :subscribers => subscribers, :tag_membership => tag_membership)

  puts '  Results:'
  stats.sort_by { |key, _| key.to_s }.each { |key, count| puts "    #{key}: #{count}" }
  puts "#{Time.now}: Kit sync finished in #{(Time.now - started).round}s."
end
