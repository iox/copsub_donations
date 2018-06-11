class HoboMigration37 < ActiveRecord::Migration
  def self.up
    add_column :donors, :force_display_as_sponsor, :boolean, :default => false
  end

  def self.down
    remove_column :donors, :force_display_as_sponsor
  end
end
