class HoboMigration25 < ActiveRecord::Migration
  def self.up
    remove_column :donors, :user_login
  end

  def self.down
    add_column :donors, :user_login, :string
  end
end
