class HoboMigration24 < ActiveRecord::Migration
  def self.up
    create_table :role_changes do |t|
      t.string   :previous_role
      t.string   :new_role
      t.datetime :created_at
      t.datetime :updated_at
      t.integer  :donor_id
    end
    add_index :role_changes, [:donor_id]
  end

  def self.down
    drop_table :role_changes
  end
end
