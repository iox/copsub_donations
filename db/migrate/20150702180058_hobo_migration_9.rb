class HoboMigration9 < ActiveRecord::Migration
  def self.up
    add_column :donations, :agilecrm_id, :string
  end

  def self.down
    remove_column :donations, :agilecrm_id
  end
end
