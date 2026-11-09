# Nightly synchronization between our donor list and Kit.com (newsletter).
# See KitSyncService for exactly what is (and is not) synchronized.
#
#   rake sync_kit_status DRY_RUN=1  # print the full plan, change NOTHING
#   rake sync_kit_status            # print the plan, then apply it
#
# The real run builds the very same plan as the dry run and executes it.
#
# Safety brake: a real run refuses to make more than MAX_KIT_WRITES Kit API
# writes (default 200; a normal night needs a handful). After checking a dry
# run, a bigger one-off run is allowed with MAX_KIT_WRITES=<number>.
#
# Cron (as user donations), under flock so two runs never overlap:
#   0 3 * * * cd /home/donations/app && /usr/bin/flock -n tmp/kit_sync.lock -c 'RAILS_ENV=production /usr/local/bin/bundle exec rake sync_kit_status >> log/kit_sync.log 2>&1'
desc 'Synchronize donors with Kit.com (DRY_RUN=1 to only print the plan)'
task :sync_kit_status => :environment do
  $stdout.sync = true # progress shows up immediately, also when piped to a log
  dry_run = %w(true 1 yes).include?(ENV['DRY_RUN'].to_s.downcase)
  max_kit_writes = (ENV['MAX_KIT_WRITES'].presence || 200).to_i
  client = KitSyncService.client
  started = Time.now

  # The sync assumes the November 2026 cleanup has run (Kit is then the source
  # of truth for newsletter statuses); before it, it would undo it.
  if Donor.where(:role => 'inactive_subscriber').exists?
    abort "*** Donors with role 'inactive_subscriber' found: run 'rake kit:cleanup' first. Nothing was changed. ***"
  end

  puts "#{Time.now}: Kit sync#{' - DRY RUN, nothing will be changed' if dry_run}"

  puts "#{Time.now}: reading all Kit subscribers..."
  subscribers = client.all_subscribers
  puts "#{Time.now}: reading category tags (segments)..."
  category_tags = client.subscriber_ids_by_tag(KitSyncService::CATEGORY_TAGS.values)
  puts "#{Time.now}: comparing with our donors..."
  donors = Donor.where("user_email IS NOT NULL AND user_email != '' AND user_email LIKE '%@%'").order(:id).to_a

  plan = KitSyncService.plan(donors, subscribers, category_tags)
  KitSyncService.print_plan(plan, subscribers)
  puts

  kit_writes = KitSyncService.kit_writes(plan)

  if dry_run
    puts '*** DRY RUN: nothing was changed. ***'
    puts "*** A real run would need MAX_KIT_WRITES=#{kit_writes} (above the default of 200). ***" if kit_writes > 200
    next
  end

  if kit_writes > max_kit_writes
    puts "*** STOPPED: this plan needs #{kit_writes} Kit API writes, more than the limit of #{max_kit_writes}. ***"
    puts '*** Nothing was changed. If the plan above is right, run again with:'
    puts "***   MAX_KIT_WRITES=#{kit_writes}"
    abort
  end

  puts "#{Time.now}: applying..."
  failed = KitSyncService.apply_plan(plan)
  puts "#{Time.now}: Kit sync finished in #{(Time.now - started).round}s, #{failed} failure(s)."
end
