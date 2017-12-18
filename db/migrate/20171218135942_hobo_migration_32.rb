class HoboMigration32 < ActiveRecord::Migration
  def self.up
    add_column :donations, :stripe_charge_id, :string
  end

  def self.down
    remove_column :donations, :stripe_charge_id
  end
end
