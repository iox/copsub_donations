class HoboMigration26 < ActiveRecord::Migration
  def self.up
    add_column :donors, :first_name, :string
    add_column :donors, :last_name, :string

    Donor.reset_column_information

    Donor.where("display_name IS NOT NULL").find_each do |donor|
      donor.update_attribute(:first_name, donor.display_name.split(' ', 2)[0])
      donor.update_attribute(:last_name, donor.display_name.split(' ', 2)[1])
    end
  end

  def self.down
    remove_column :donors, :first_name
    remove_column :donors, :last_name
  end
end
