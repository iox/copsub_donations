class HoboMigration6 < ActiveRecord::Migration
  def self.up
    add_column :donations, :user_assigned, :boolean, :default => false
  end

  def self.down
    remove_column :donations, :user_assigned
  end
end
