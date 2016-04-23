class HoboMigration16 < ActiveRecord::Migration
  def self.up
    add_column :donors, :notes, :text
  end

  def self.down
    remove_column :donors, :notes
  end
end
