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

end
