class HoboMigration4 < ActiveRecord::Migration
  def self.up
    add_column :donations, :donation_method, :string
  end

  def self.down
    remove_column :donations, :donation_method
  end
end
