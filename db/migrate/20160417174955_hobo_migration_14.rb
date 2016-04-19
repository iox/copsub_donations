class HoboMigration14 < ActiveRecord::Migration
  def self.up
    add_column :donors, :in_mailchimp_list, :boolean, :default => false
  end

  def self.down
    remove_column :donors, :in_mailchimp_list
  end
end
