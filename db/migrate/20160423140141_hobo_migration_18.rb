class HoboMigration18 < ActiveRecord::Migration
  def self.up
    add_column :donors, :donation_method, :string
  end

  def self.down
    remove_column :donors, :donation_method
  end
end
