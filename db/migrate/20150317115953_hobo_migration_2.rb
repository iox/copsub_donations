class HoboMigration2 < ActiveRecord::Migration
  def self.up
    add_column :donations, :seamless_donation_id, :integer
  end

  def self.down
    remove_column :donations, :seamless_donation_id
  end
end
