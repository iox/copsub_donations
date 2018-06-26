class HoboMigration38 < ActiveRecord::Migration
  def self.up
    create_table :notes do |t|
      t.text     :body
      t.datetime :created_at
      t.datetime :updated_at
      t.integer  :donor_id
    end
    
    rename_column :donors, :notes, :old_notes_backup
    
    
    add_index :notes, [:donor_id]
    
    
  end

  def self.down
    drop_table :notes
    rename_column :donors, :old_notes_backup, :notes
  end
end
