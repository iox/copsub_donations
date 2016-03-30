class HoboMigration9 < ActiveRecord::Migration
  def self.up
    create_table :donors do |t|
      t.integer  :wordpress_id
      t.string   :user_email
      t.string   :user_login
      t.string   :display_name
      t.text     :user_adress
      t.string   :city
      t.string   :country
      t.integer  :paymentid
      t.integer  :paypal_id
      t.string   :user_phone
      t.integer  :donated_last_year_in_dkk
      t.string   :role
      t.datetime :created_at
      t.datetime :updated_at
    end
  end

  def self.down
    drop_table :donors
  end
end
