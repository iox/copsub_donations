class HoboMigration13 < ActiveRecord::Migration
  def self.up
    add_column :donors, :first_donation, :date
    Donor.reset_column_information

    for donor in Donor.all
      donor.update_amount_donated_last_year!
    end
  end

  def self.down
    remove_column :donors, :first_donation
  end
end
