class HoboMigration11 < ActiveRecord::Migration
  def self.up
    add_column :donors, :alternative_id, :string
    change_column :donors, :paymentid, :string, :limit => 255
    change_column :donors, :paypal_id, :string, :limit => 255
  end

  def self.down
    remove_column :donors, :alternative_id
    change_column :donors, :paymentid, :integer
    change_column :donors, :paypal_id, :integer
  end
end
