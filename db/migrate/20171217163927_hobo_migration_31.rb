class HoboMigration31 < ActiveRecord::Migration
  def self.up
    add_column :donors, :stopped_regular_donations_date, :date
  end

  def self.down
    remove_column :donors, :stopped_regular_donations_date
  end
end
