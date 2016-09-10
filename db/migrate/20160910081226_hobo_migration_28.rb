class HoboMigration28 < ActiveRecord::Migration
  def self.up
    create_table :email_logs do |t|
      t.string   :email
      t.string   :subject
      t.datetime :created_at
      t.datetime :updated_at
    end
  end

  def self.down
    drop_table :email_logs
  end
end
