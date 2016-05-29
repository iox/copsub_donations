class HoboMigration20 < ActiveRecord::Migration
  def self.up
    add_column :donations, :notes, :text
  end

  def self.down
    remove_column :donations, :notes
  end
end
