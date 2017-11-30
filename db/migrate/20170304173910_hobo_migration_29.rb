class HoboMigration29 < ActiveRecord::Migration
  def self.up
    add_column :donors, :selected_donor_type, :string
    add_column :donors, :selected_amount, :integer
  end

  def self.down
    remove_column :donors, :selected_donor_type
    remove_column :donors, :selected_amount
  end
end
