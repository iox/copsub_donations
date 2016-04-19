class HoboMigration15 < ActiveRecord::Migration
  def self.up
    add_column :donors, :mailchimp_status, :string, :default => "not_present"
    remove_column :donors, :in_mailchimp_list
  end

  def self.down
    remove_column :donors, :mailchimp_status
    add_column :donors, :in_mailchimp_list, :boolean, default: false
  end
end
