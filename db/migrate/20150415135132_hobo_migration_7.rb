class HoboMigration7 < ActiveRecord::Migration
  def self.up
    add_column :donations, :other_income, :boolean, :default => false
  end

  def self.down
    remove_column :donations, :other_income
  end
end
