class HoboMigration35 < ActiveRecord::Migration
  def self.up
    add_column :donors, :filled_donation_form_date, :date
  end

  def self.down
    remove_column :donors, :filled_donation_form_date
  end
end
