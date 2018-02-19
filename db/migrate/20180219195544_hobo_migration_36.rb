class HoboMigration36 < ActiveRecord::Migration
  def self.up
    add_column :donors, :custom_donation_interval, :integer
  end

  def self.down
    remove_column :donors, :custom_donation_interval
  end
end
