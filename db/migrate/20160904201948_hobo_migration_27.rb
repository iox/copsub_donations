class HoboMigration27 < ActiveRecord::Migration
  def self.up
    remove_column :donors, :display_name
  end

  def self.down
    add_column :donors, :display_name, :string
  end
end
