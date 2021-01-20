PayPal::SDK::REST.set_config(
      :mode => ENV['PAYPAL_MODE'],
      :client_id => ENV['PAYPAL_CSS_CLIENT_ID'],
      :client_secret => ENV['PAYPAL_CSS_SECRET'],
      # Deliberately set ca_file to nil so the system's Cert Authority is used,
      # instead of the bundled paypal.crt file which is out-of-date due to:
      # https://www.paypal.com/va/smarthelp/article/discontinue-use-of-verisign-g5-root-certificates-ts2240
      ssl_options: { ca_file: nil })