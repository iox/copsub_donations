class HoboMigration22 < ActiveRecord::Migration
  def self.up
    add_column :paypal_events, :address_street, :string
    add_column :paypal_events, :address_zip, :string
    add_column :paypal_events, :address_country_code, :string
    add_column :paypal_events, :address_name, :string
    add_column :paypal_events, :address_city, :string
    add_column :paypal_events, :address_state, :string
    add_column :paypal_events, :address_country, :string
    add_column :paypal_events, :txn_id, :string
    add_column :paypal_events, :payment_type, :string
    add_column :paypal_events, :payment_fee, :string
    add_column :paypal_events, :transaction_subject, :string
  end

  def self.down
    remove_column :paypal_events, :address_street
    remove_column :paypal_events, :address_zip
    remove_column :paypal_events, :address_country_code
    remove_column :paypal_events, :address_name
    remove_column :paypal_events, :address_city
    remove_column :paypal_events, :address_state
    remove_column :paypal_events, :address_country
    remove_column :paypal_events, :txn_id
    remove_column :paypal_events, :payment_type
    remove_column :paypal_events, :payment_fee
    remove_column :paypal_events, :transaction_subject
  end
end
