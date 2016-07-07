class HoboMigration23 < ActiveRecord::Migration
  def self.up
    add_column :donors, :last_paypal_failure, :date
  end

  def self.down
    remove_column :donors, :last_paypal_failure
  end
end
