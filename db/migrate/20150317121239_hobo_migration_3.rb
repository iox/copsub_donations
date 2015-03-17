class HoboMigration3 < ActiveRecord::Migration
  def self.up
    change_column :donations, :donated_at, :datetime
  end

  def self.down
    change_column :donations, :donated_at, :time
  end
end
