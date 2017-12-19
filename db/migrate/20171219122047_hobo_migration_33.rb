class HoboMigration33 < ActiveRecord::Migration
  def self.up
    add_column :donations, :first_donation_in_series, :boolean, :default => false
    add_column :donations, :last_donation_in_series, :boolean, :default => false
    add_column :donations, :stopped_donating_date, :date
  end

  def self.down
    remove_column :donations, :first_donation_in_series
    remove_column :donations, :last_donation_in_series
    remove_column :donations, :stopped_donating_date
  end
end
