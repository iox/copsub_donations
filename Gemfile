source 'https://rubygems.org'

# Bundle edge Rails instead: gem 'rails', github: 'rails/rails'
gem 'rails', '4.0.13'

# Use mysql as the database for Active Record
gem 'mysql2', '~> 0.3.18'

# Use SCSS for stylesheets
gem 'sass-rails', '~> 4.0.2'

# Use Uglifier as compressor for JavaScript assets
gem 'uglifier', '>= 1.3.0'

# Use CoffeeScript for .js.coffee assets and views
gem 'coffee-rails', '~> 4.0.0'

# See https://github.com/sstephenson/execjs#readme for more supported runtimes
# gem 'therubyracer', platforms: :ruby

# Use jquery as the JavaScript library
gem 'jquery-rails'

# Turbolinks makes following links in your web application faster. Read more: https://github.com/rails/turbolinks
gem 'turbolinks'

# Build JSON APIs with ease. Read more: https://github.com/rails/jbuilder
gem 'jbuilder', '~> 1.2'

group :doc do
  # bundle exec rake doc:rails generates the API under doc/api.
  gem 'sdoc', require: false
end

# Use ActiveModel has_secure_password
# gem 'bcrypt', '~> 3.1.7'

# Use unicorn as the app server
# gem 'unicorn'

# Use Capistrano for deployment
# gem 'capistrano', group: :development

# Use debugger
# gem 'debugger', group: [:development, :test]

gem "hobo", "= 2.1.1"
gem "protected_attributes"
# Hobo has a lot of assets.   Stop cluttering the log in development mode.
gem "quiet_assets", group: :development
# Hobo's version of will_paginate is required.
gem "hobo_will_paginate"
gem "hobo_bootstrap", "2.1.1"
gem "hobo_jquery_ui", "2.1.1"
gem "hobo_bootstrap_ui", "2.1.1"
gem "jquery-ui-themes", "~> 0.0.4"
gem "hobo_clean_admin", "2.1.1"
gem 'hobo-metasearch', :git => "https://github.com/iox/hobo-metasearch"
gem 'charlock_holmes' # Autodetect imported CSV encoding
gem 'php_serialize' # Parse serialized arrays from the Wordpress database
gem 'render_csv'

group :development do
  gem "better_errors"
  gem "binding_of_caller"
end

group :development, :test do
  gem 'rspec-rails'
  gem 'factory_bot'
  gem 'shoulda-matchers'
  gem 'guard-rspec', require: false
  gem 'capybara'
  gem 'poltergeist'
  gem 'capybara-screenshot'
end


#gem 'agilecrm-wrapper', github: 'iox/agilecrm-wrapper'
gem 'thin'

# Handle Paypal IPN
gem 'offsite_payments'

# Connect to Paypal's API to generate Payment Tokens
gem 'paypal-sdk-rest'

# Connecting to Paypal Sync API - using oauth directly
gem 'httparty'

# Send an email when an error occurs
gem 'exception_notification'

# Connect to Mailchimp
gem 'gibbon'

# Memcache client
gem 'dalli'

# Connect to Stripe
gem 'stripe'

# Load .env files
gem 'dotenv-rails'
