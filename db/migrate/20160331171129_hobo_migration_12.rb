class HoboMigration12 < ActiveRecord::Migration
  def self.up
    rename_column :donors, :paypal_id, :paypalid
    rename_column :donors, :alternative_id, :alternativeid
  end

  def self.down
    rename_column :donors, :paypalid, :paypal_id
    rename_column :donors, :alternativeid, :alternative_id
  end
end
