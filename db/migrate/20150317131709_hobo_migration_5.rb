class HoboMigration5 < ActiveRecord::Migration
  def self.up
    add_column :donations, :wordpress_user_id, :integer
  end

  def self.down
    remove_column :donations, :wordpress_user_id
  end
end
