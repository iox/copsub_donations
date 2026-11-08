# Nightly synchronization between our donor list and Kit.com (newsletter).
#
#   rake sync_kit_status            # pull subscriber statuses from Kit, then
#                                   # push donors changed since the last run
#   rake sync_kit_status FULL=true  # push ALL donors (slow: rate limited to
#                                   # ~1 API request/second). Only donors who
#                                   # opted into the newsletter are created in
#                                   # Kit; others are only updated if they
#                                   # already exist as subscribers there.
#   rake sync_kit_status LIMIT=20   # only push the first 20 changed donors (testing)
#
# Real-time subscription/unsubscription events arrive through the Kit webhooks
# (KitWebhooksController), so this task is mainly about donor data flowing into
# Kit (roles, categories, custom fields) and about reconciling anything the
# webhooks missed.
desc 'Synchronize donors with Kit.com (push changed donors, pull subscriber statuses)'
task :sync_kit_status => :environment do

  full  = %w(true 1 yes).include?(ENV['FULL'].to_s.downcase)
  limit = ENV['LIMIT'].to_i

  # Per-donor fingerprints of what we last pushed to Kit. Kept out of the
  # database on purpose; if it is lost, the next run is a (harmless) full push.
  state_file = Rails.root.join('tmp', 'kit_push_state.json')
  state = File.exist?(state_file) ? JSON.parse(File.read(state_file)) : {}

  # --- 1. PULL: subscriber states from Kit ----------------------------------
  # Runs FIRST, so that the push below makes its create/update decisions with
  # up-to-date subscription states (Kit is the source of truth for those).

  puts 'PULL: reading subscriber statuses from Kit...'
  affected = 0
  after = nil
  loop do
    page = KitSyncService.client.subscribers_page(:status => 'all', :per_page => 500, :after => after)
    (page['subscribers'] || []).each do |subscriber|
      donor = KitSyncService.apply_subscriber_state(subscriber['email_address'], subscriber['state'], subscriber['first_name'])
      affected += 1 if donor
    end

    pagination = page['pagination'] || {}
    break unless pagination['has_next_page']
    after = pagination['end_cursor']
  end
  puts "PULL done: #{affected} donor(s) created/updated from Kit subscriber states."

  # --- 2. PUSH: donors whose relevant data changed since the last run -------

  donors = Donor.where("user_email IS NOT NULL AND user_email != '' AND user_email LIKE '%@%'").order(:id)
  donors = donors.limit(limit) if limit > 0

  total = donors.count
  queue = []
  donors.each { |donor| queue << donor if full || state[donor.id.to_s] != KitSyncService.fingerprint(donor) }

  puts "PUSH: #{queue.size}/#{total} donor(s) changed since the last run#{' (FULL sync)' if full}."

  pushed = 0
  failed = 0
  queue.each_with_index do |donor, index|
    begin
      KitSyncService.push_donor(donor)
      state[donor.id.to_s] = KitSyncService.fingerprint(donor)
      pushed += 1
    rescue => e
      failed += 1
      puts "  ! Donor #{donor.id} (#{donor.user_email}) could not be pushed: #{e.message}"
    end
    puts "  ... pushed #{pushed}/#{queue.size}" if ((index + 1) % 50).zero?
  end
  puts "PUSH done: #{pushed} synchronized, #{failed} failed."

  FileUtils.mkdir_p(File.dirname(state_file))
  File.open(state_file, 'w') { |f| f.write(JSON.generate(state)) }

  puts 'Kit sync finished.'
end
