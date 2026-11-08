# Minimal HTTP client for the Kit.com (formerly ConvertKit) V4 API.
#
# Docs: https://developers.kit.com/api-reference/overview
# Auth: account API secret key (Account Settings -> API), sent as X-Kit-Api-Key.
#
# Kit rate limits the API to roughly 60 requests/minute per key, so this
# client throttles itself to at most one request per second.
class KitClient

  BASE_URL = 'https://api.kit.com/v4'
  MIN_SECONDS_BETWEEN_REQUESTS = 1.0

  class Error < StandardError; end

  def initialize(api_key = KIT_API_KEY)
    raise Error, 'KIT_API_KEY is not configured' if api_key.blank?
    @api_key = api_key
    @last_request_at = nil
  end

  # --- Subscribers ---

  # Upsert: creates the subscriber if unknown, updates the first name otherwise.
  # Returns the subscriber as a Hash (including its 'id').
  def upsert_subscriber(email_address, first_name: nil)
    body = { :email_address => email_address }
    body[:first_name] = first_name if first_name.present?
    json(post('/subscribers', body))['subscriber']
  end

  # Returns the subscriber Hash for an exact email address, or nil.
  # NOTE: do NOT pass status:'all' together with email_address - Kit returns an
  # empty list for that combination. Default (active) works fine.
  def subscriber(email_address)
    (json(get('/subscribers', :email_address => email_address, :slim => true))['subscribers'] || []).first
  end

  # Updates first name and/or custom field values (Hash of key => value).
  # Unknown field keys are ignored by Kit (reported as warnings).
  def update_subscriber(subscriber_id, email_address, first_name: nil, fields: {})
    body = { :email_address => email_address }
    body[:first_name] = first_name if first_name.present?
    body[:fields] = fields.stringify_keys if fields.present?
    json(put("/subscribers/#{subscriber_id}", body))['subscriber']
  end

  def unsubscribe(subscriber_id)
    post("/subscribers/#{subscriber_id}/unsubscribe", {})
    true
  end

  # One page of subscribers. Options: :status ('active', 'inactive', 'cancelled',
  # 'bounced', 'complained', 'all'), :per_page (default 500, max 1000),
  # :after (the 'end_cursor' of the previous page).
  # Returns a Hash with 'subscribers' and 'pagination'.
  def subscribers_page(status: 'all', per_page: 500, after: nil)
    params = { :status => status, :per_page => per_page }
    params[:after] = after if after.present?
    json(get('/subscribers', params))
  end

  # --- Tags ---

  # All tags currently applied to a subscriber (follows pagination).
  def tags_for_subscriber(subscriber_id)
    tags = []
    after = nil
    loop do
      path = "/subscribers/#{subscriber_id}/tags"
      path += "?after=#{after}" if after.present?
      page = json(get_raw(path))
      tags += (page['tags'] || [])
      pagination = page['pagination'] || {}
      break unless pagination['has_next_page']
      after = pagination['end_cursor']
    end
    tags
  end

  # Tags an existing subscriber, by email address. Idempotent.
  def add_tag(tag_id, email_address)
    post("/tags/#{tag_id}/subscribers", :email_address => email_address)
    true
  end

  # Removes a tag from a subscriber, by subscriber id.
  def remove_tag(tag_id, subscriber_id)
    delete("/tags/#{tag_id}/subscribers/#{subscriber_id}")
    true
  end

  # --- Forms ---

  # Adds an existing subscriber to a form, by email address.
  # NOTE: on double opt-in forms this triggers the incentive email.
  def add_subscriber_to_form_by_email(form_id, email_address)
    post("/forms/#{form_id}/subscribers", :email_address => email_address)
    true
  end

  # --- Webhooks (legacy) ---
  # NOTE: the new /v4/webhook_endpoints API does not accept API-key
  # authentication on this account (401), so we use the legacy webhooks API,
  # which works with the API key. Deliveries are authenticated with a shared
  # secret embedded in the callback URL.

  def webhooks
    json(get('/webhooks', {}))['webhooks'] || []
  end

  # Subscribes to one event, e.g. 'subscriber.subscriber_activate'.
  def create_webhook(target_url, event_name)
    json(post('/webhooks', :target_url => target_url, :event => { :name => event_name }))['webhook']
  end

  def destroy_webhook(webhook_id)
    delete("/webhooks/#{webhook_id}")
    true
  end

  private

  def get(path, params = {})
    request(:get, path, :query => params)
  end

  # For paths that already contain a query string.
  def get_raw(path_with_query)
    request(:get, path_with_query, {})
  end

  def post(path, body)
    request(:post, path, :body => body.to_json)
  end

  def put(path, body)
    request(:put, path, :body => body.to_json)
  end

  def delete(path)
    request(:delete, path, {})
  end

  def request(verb, path, options)
    throttle!

    options = { :headers => default_headers, :timeout => 20 }.merge(options)
    response = HTTParty.send(verb, "#{BASE_URL}#{path}", options)

    # Be nice if we ever hit the rate limit anyway
    if response.code == 429
      sleep(10)
      response = HTTParty.send(verb, "#{BASE_URL}#{path}", options)
    end

    unless response.code.between?(200, 299)
      raise Error, "Kit API #{verb.to_s.upcase} #{path} returned #{response.code}: #{response.body.to_s[0..300]}"
    end

    response
  end

  def default_headers
    { 'X-Kit-Api-Key' => @api_key, 'Content-Type' => 'application/json', 'Accept' => 'application/json' }
  end

  def json(response)
    return {} if response.body.blank?
    JSON.parse(response.body)
  rescue JSON::ParserError
    raise Error, "Kit API returned invalid JSON: #{response.body.to_s[0..200]}"
  end

  def throttle!
    if @last_request_at
      elapsed = Time.now - @last_request_at
      sleep(MIN_SECONDS_BETWEEN_REQUESTS - elapsed) if elapsed < MIN_SECONDS_BETWEEN_REQUESTS
    end
    @last_request_at = Time.now
  end

end
