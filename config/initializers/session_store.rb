# Be sure to restart your server when you modify this file.

# CopsubDonations::Application.config.session_store :cookie_store, key: '_copsub_donations_session'

CopsubDonations::Application.config.session_store :mem_cache_store, key: '_copsub_donations_session'
CopsubDonations::Application.config.cache_store = :mem_cache_store, 'localhost', '127.0.0.1:11211',
{:namespace => 'copsub_donations'}