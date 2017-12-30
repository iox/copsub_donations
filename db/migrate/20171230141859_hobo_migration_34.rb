class HoboMigration34 < ActiveRecord::Migration
  def self.up
    change_column :donors, :number_of_donations, :integer, :limit => 4, :default => 0
  end

  def self.down
    change_column :donors, :number_of_donations, :integer
  end
end
