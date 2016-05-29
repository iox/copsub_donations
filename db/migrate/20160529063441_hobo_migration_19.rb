class HoboMigration19 < ActiveRecord::Migration
  def self.up
    create_table :saved_searches do |t|
      t.string   :name
      t.text     :path
      t.datetime :created_at
      t.datetime :updated_at
    end
  end

  def self.down
    drop_table :saved_searches
  end
end
