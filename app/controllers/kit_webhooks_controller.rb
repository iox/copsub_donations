# Receives webhook deliveries from Kit.com.
#
# The endpoint is registered with `rake kit:setup_webhooks`.
#
# Two delivery styles are accepted and authenticated:
#
#  * Legacy webhooks (POST /v4/webhooks, the only style this account's API key
#    can currently manage). These carry no signature, so the callback URL
#    includes a shared secret: /api/kit/webhook?secret=<KIT_WEBHOOK_SECRET>.
#  * New-style webhook endpoints (POST /v4/webhook_endpoints), which deliver an
#    envelope of events signed with an HMAC in the X-Kit-Signature header,
#    keyed with the endpoint secret (also stored in KIT_WEBHOOK_SECRET).
#    https://developers.kit.com/webhooks/verifying-signatures
#
# Until KIT_WEBHOOK_SECRET is configured, every delivery is rejected.
class KitWebhooksController < ApplicationController

  SIGNATURE_TOLERANCE_SECONDS = 300

  # Legacy events do not carry the subscriber state; derive it from the event.
  LEGACY_EVENT_STATES = {
    'subscriber_activate'             => 'active',
    'subscriber_unsubscribe'          => 'cancelled',
    'subscriber_bounce'               => 'bounced',
    'subscriber_complain'             => 'complained',
  }

  HANDLED_NEW_STYLE_EVENTS = %w{
    subscriber.created
    subscriber.activated
    subscriber.subscribed_to_form
    subscriber.unsubscribed
    subscriber.bounced
    subscriber.complained
  }

  skip_before_filter :authenticate
  protect_from_forgery :except => [:create]

  def create
    raw_body = request.body.read
    request.body.rewind

    unless delivery_authorized?(raw_body)
      Rails.logger.warn 'Kit webhook rejected: authentication failed (is KIT_WEBHOOK_SECRET set correctly?)'
      head :unauthorized
      return
    end

    payload = JSON.parse(raw_body)
    events = payload['events']

    if events.is_a?(Array)
      # New-style envelope: 1..100 same-type events; retries reuse event ids and
      # all our handlers are idempotent.
      events.each do |event|
        process_event(event['type'].to_s, (event['data'] || {})['subscriber'] || {})
      end
      processed = events.size
    else
      # Legacy delivery: a 'subscriber' object (with its state). The body does
      # not name the event, so each legacy webhook registers its own callback
      # URL carrying ?event=<name> as a fallback for the subscriber state.
      subscriber =
        if payload['subscriber'].is_a?(Hash)
          payload['subscriber']
        else
          { 'id' => payload['subscriber_id'], 'email_address' => payload['email_address'], 'first_name' => payload['first_name'] }
        end
      name = legacy_event_name(payload).presence || params[:event].to_s
      process_event(name, subscriber, LEGACY_EVENT_STATES[name.sub('subscriber.', '')])
      processed = 1
    end

    render :json => { :status => 'ok', :processed => processed }
  rescue => e
    # Answer 5xx so that Kit retries the delivery later
    Rails.logger.error "Kit webhook error: #{e.class}: #{e.message}\n#{e.backtrace.to_s[0..1000]}"
    head :internal_server_error
  end

  private

  def process_event(type, subscriber, derived_state = nil)
    email = subscriber['email_address']
    state = subscriber['state'] || derived_state

    Rails.logger.info "Kit webhook: #{type} for #{email} (state: #{state})"
    return if email.blank? || state.blank?

    if type.present? && !HANDLED_NEW_STYLE_EVENTS.include?(type) && LEGACY_EVENT_STATES[type.sub('subscriber.', '')].nil?
      Rails.logger.info "Kit webhook: ignoring event type '#{type}'"
      return
    end

    KitSyncService.apply_subscriber_state(email, state, subscriber['first_name'])
  end

  def legacy_event_name(payload)
    name = payload['event']
    name = name['name'] if name.is_a?(Hash)
    (name || payload['event_name'] || payload['type']).to_s
  end

  def delivery_authorized?(raw_body)
    header = request.headers['X-Kit-Signature']
    return valid_signature?(raw_body, header) if header.present?
    valid_url_secret?
  end

  # Constant-time string comparison. ActiveSupport::SecurityUtils only exists
  # from Rails 4.1+; this app is on Rails 4.0, so we inline the same
  # implementation here.
  def secure_compare(a, b)
    a = a.to_s
    b = b.to_s
    return false unless a.bytesize == b.bytesize
    bytes = a.unpack('C*')
    res = 0
    b.each_byte { |byte| res |= byte ^ bytes.shift }
    res == 0
  end

  # Legacy webhooks: shared secret in the callback URL's ?secret= parameter.
  def valid_url_secret?
    secret = ENV['KIT_WEBHOOK_SECRET']
    given = params[:secret].to_s
    return false if secret.blank? || given.blank?
    secure_compare(given, secret)
  end

  # New-style webhooks: header "t=<unix ts>,v1=<hex>[,v1=<hex>...]" with an
  # HMAC-SHA256 of "<t>.<raw body>" keyed with the endpoint secret.
  def valid_signature?(raw_body, header)
    secret = ENV['KIT_WEBHOOK_SECRET']
    return false if secret.blank? || header.blank?

    parts = header.to_s.split(',').map(&:strip)

    timestamp = nil
    parts.each do |part|
      timestamp = part[2..-1] if timestamp.nil? && part.start_with?('t=')
    end
    return false if timestamp.nil?
    return false if (Time.now.to_i - timestamp.to_i).abs > SIGNATURE_TOLERANCE_SECONDS

    expected = OpenSSL::HMAC.hexdigest(OpenSSL::Digest::SHA256.new, secret, "#{timestamp}.#{raw_body}")

    candidates = []
    parts.each do |part|
      candidates << part[3..-1] if part.start_with?('v1=')
    end

    candidates.any? do |candidate|
      candidate.length == expected.length && secure_compare(candidate, expected)
    end
  end

end
