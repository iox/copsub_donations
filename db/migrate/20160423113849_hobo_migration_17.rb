class HoboMigration17 < ActiveRecord::Migration
  def self.up
    rename_column :donors, :first_donation, :first_donated_at
    add_column :donors, :donated_total, :integer
    add_column :donors, :last_donated_at, :date
  end

  def self.down
    rename_column :donors, :first_donated_at, :first_donation
    remove_column :donors, :donated_total
    remove_column :donors, :last_donated_at
  end
end
