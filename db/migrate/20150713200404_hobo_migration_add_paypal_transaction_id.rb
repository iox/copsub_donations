class HoboMigrationAddPaypalTransactionId < ActiveRecord::Migration
  def self.up
    add_column :donations, :paypal_transaction_id, :string
  end

  def self.down
    remove_column :donations, :paypal_transaction_id
  end
end
