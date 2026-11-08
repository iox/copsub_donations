namespace :kit do

  # Kit's new webhook API (/v4/webhook_endpoints, signed deliveries) does not
  # accept API-key authentication on our account yet, so we register legacy
  # webhooks (/v4/webhooks). They deliver the subscriber object without a
  # signature, so the callback URL carries a shared secret, and one webhook is
  # registered per event (the legacy payload does not name its event).

  desc 'Register the Kit.com webhooks for this app (uses/generates KIT_WEBHOOK_SECRET)'
  task :setup_webhooks => :environment do
    base_url = ENV['URL'] || 'https://donations.copsub.dk/api/kit/webhook'
    secret = ENV['KIT_WEBHOOK_SECRET'].presence || SecureRandom.hex(32)

    events = %w{
      subscriber.subscriber_activate
      subscriber.subscriber_unsubscribe
      subscriber.subscriber_bounce
      subscriber.subscriber_complain
    }

    client = KitClient.new
    existing = client.webhooks

    events.each do |event_name|
      short_name = event_name.sub('subscriber.', '')
      callback = "#{base_url}?secret=#{secret}&event=#{short_name}"

      already = existing.find do |w|
        (w['event'] || {})['name'].to_s.sub('subscriber.', '') == short_name &&
          w['target_url'].to_s.split('?').first == base_url
      end

      if already
        puts "OK, webhook for '#{event_name}' already exists (id #{already['id']})."
      else
        client.create_webhook(callback, event_name)
        puts "Created webhook for '#{event_name}'."
      end
    end

    puts
    puts 'IMPORTANT - the callback secret must match KIT_WEBHOOK_SECRET on the server:'
    puts "  KIT_WEBHOOK_SECRET=#{secret}"
    puts '(e.g. in .env.production, then restart the app; deliveries are rejected otherwise)'
  end

  desc 'List the Kit.com webhooks currently registered'
  task :webhooks => :environment do
    webhooks = KitClient.new.webhooks
    if webhooks.empty?
      puts 'No webhooks registered. Run: rake kit:setup_webhooks'
    else
      webhooks.each do |w|
        url = w['target_url'].to_s
        url = url.sub(/secret=[0-9a-f]+/, 'secret=<hidden>')
        puts "  #{w['id']}: #{(w['event'] || {})['name']} -> #{url}"
      end
    end
  end

  # One-off repair (November 2026): a bulk pull that still trusted the October
  # import's 'active' states flipped some donors who had unsubscribed in
  # Mailchimp back to 'subscribed'. This restores them from a pre-incident
  # donor dump (tab-separated, header row; email in column 4, mailchimp_status
  # in column 10).
  #
  # A donor is restored to 'unsubscribed' only when ALL of these hold:
  #   - the dump says 'unsubscribed' and the app now says 'subscribed'
  #   - their Kit subscriber is missing, or was created before the import
  #     cutoff (people who signed up after it opted in for real)
  #
  #   rake kit:restore_unsubscribed TSV=/path/donors_raw.tsv           # dry run
  #   rake kit:restore_unsubscribed TSV=/path/donors_raw.tsv APPLY=1   # apply
  desc 'Restore donors wrongly re-subscribed by the Kit pull, from a donor dump'
  task :restore_unsubscribed => :environment do
    path = ENV['TSV'].to_s
    abort 'Usage: rake kit:restore_unsubscribed TSV=/path/donors_raw.tsv [APPLY=1]' unless File.exist?(path)
    apply = %w(true 1 yes).include?(ENV['APPLY'].to_s.downcase)

    unsubscribed_emails = Set.new
    File.readlines(path, :encoding => 'UTF-8').drop(1).each do |line|
      cols = line.chomp.split("\t", -1)
      email = cols[3].to_s.strip.downcase
      unsubscribed_emails << email if email.present? && cols[9].to_s.strip == 'unsubscribed'
    end
    puts "#{unsubscribed_emails.size} unsubscribed address(es) in the dump."

    puts 'Reading Kit subscribers...'
    subscribers = KitSyncService.client.all_subscribers

    restored = 0
    kept = 0
    Donor.where(:mailchimp_status => 'subscribed').find_each do |donor|
      email = donor.user_email.to_s.strip.downcase
      next unless unsubscribed_emails.include?(email)

      subscriber = subscribers[email]
      if subscriber && KitSyncService.kit_state_authoritative?(subscriber)
        kept += 1
        puts "  keep    donor #{donor.id} (#{email}): signed up in Kit on #{subscriber['created_at']}"
        next
      end

      puts "  #{apply ? 'restore' : 'would restore'} donor #{donor.id} (#{email})"
      restored += 1
      next unless apply

      # Direct setter: mailchimp_status is not attr_accessible.
      donor.mailchimp_status = 'unsubscribed'
      donor.role = 'inactive_subscriber' if donor.role == 'subscriber'
      donor.save!
    end

    puts "#{restored} donor(s) #{apply ? 'restored' : 'would be restored'}, #{kept} kept (genuine new Kit signups)."
    puts 'Dry run - nothing changed. Re-run with APPLY=1 to apply.' unless apply
  end

end
