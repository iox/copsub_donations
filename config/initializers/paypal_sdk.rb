PayPal::SDK::REST.set_config(
      :mode => ENV['PAYPAL_MODE'],
      :client_id => ENV['PAYPAL_CLIENT_ID'],
      :client_secret => ENV['PAYPAL_SECRET'])