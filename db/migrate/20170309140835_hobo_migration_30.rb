class HoboMigration30 < ActiveRecord::Migration
  def self.up
    add_column :donors, :stripe_customer_id, :string
    add_column :donors, :stripe_card_expiration_date, :date
  end

  def self.down
    remove_column :donors, :stripe_customer_id
    remove_column :donors, :stripe_card_expiration_date
  end
end
