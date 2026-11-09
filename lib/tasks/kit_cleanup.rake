namespace :kit do

  # Read-only health check: data problems and every difference between our
  # database and Kit. Changes nothing.
  #
  #   rake kit:audit
  desc 'Read-only: check that our donors and Kit.com are 100% in sync'
  task :audit => :environment do
    $stdout.sync = true
    client = KitSyncService.client
    puts "#{Time.now}: reading Kit..."
    subscribers = client.all_subscribers
    category_tags = client.subscriber_ids_by_tag(KitSyncService::CATEGORY_TAGS.values)
    donors = Donor.where("user_email IS NOT NULL AND user_email != '' AND user_email LIKE '%@%'").order(:id).to_a
    KitCleanup.audit(donors, subscribers, category_tags)
  end

  # One-off cleanup (November 2026), see KitCleanup. Separates newsletter
  # status from donor type, merges duplicate donors and aligns statuses with
  # Kit. Dry run unless APPLY=1; the real run applies exactly the printed plan.
  #
  #   rake kit:cleanup           > /tmp/kit_cleanup_plan.txt   # dry run
  #   rake kit:cleanup APPLY=1   > /tmp/kit_cleanup_done.txt   # apply
  desc 'One-off: clean up roles/newsletter statuses and align with Kit.com (APPLY=1 to apply)'
  task :cleanup => :environment do
    $stdout.sync = true
    apply = %w(true 1 yes).include?(ENV['APPLY'].to_s.downcase)
    puts "#{Time.now}: Kit cleanup#{apply ? '' : ' - DRY RUN, nothing will be changed'}"

    puts "#{Time.now}: reading Kit..."
    subscribers = KitSyncService.client.all_subscribers
    donors = Donor.where("user_email IS NOT NULL AND user_email != '' AND user_email LIKE '%@%'").order(:id).to_a

    plan = KitCleanup.plan(donors, subscribers)
    KitCleanup.print_plan(plan)
    puts

    unless apply
      puts '*** DRY RUN: nothing was changed. Run again with APPLY=1 to apply exactly this plan. ***'
      next
    end

    puts "#{Time.now}: applying..."
    failed = KitCleanup.apply_plan(plan)
    puts "#{Time.now}: cleanup finished, #{failed} failure(s)."
    puts 'Next: rake sync_kit_status DRY_RUN=1, then rake kit:audit.'
  end

end
