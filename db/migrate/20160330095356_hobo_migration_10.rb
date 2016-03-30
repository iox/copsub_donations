class HoboMigration10 < ActiveRecord::Migration
  def self.up
    add_column :donations, :donor_id, :integer

    add_index :donations, [:donor_id]
  end

  def self.down
    remove_column :donations, :donor_id

    remove_index :donations, :name => :index_donations_on_donor_id rescue ActiveRecord::StatementInvalid
  end
end
