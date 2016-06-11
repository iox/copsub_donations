class HoboMigration21 < ActiveRecord::Migration
  def self.up
    create_table :paypal_events do |t|
      t.string   :txn_type
      t.string   :subscr_id
      t.string   :last_name
      t.string   :residence_country
      t.string   :item_name
      t.string   :mc_currency
      t.string   :business
      t.string   :verify_sign
      t.string   :payer_status
      t.string   :payer_email
      t.string   :first_name
      t.string   :receiver_email
      t.string   :payer_id
      t.string   :item_number
      t.string   :charset
      t.string   :notify_version
      t.string   :ipn_track_id
      t.datetime :created_at
      t.datetime :updated_at
    end
  end

  def self.down
    drop_table :paypal_events
  end
end
