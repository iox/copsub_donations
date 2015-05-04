class HoboMigration8 < ActiveRecord::Migration
  def self.up
    create_table :categories do |t|
      t.string   :name
      t.boolean  :default, :default => false
      t.datetime :created_at
      t.datetime :updated_at
    end

    add_column :donations, :category_id, :integer

    add_index :donations, [:category_id]
  end

  def self.down
    remove_column :donations, :category_id

    drop_table :categories

    remove_index :donations, :name => :index_donations_on_category_id rescue ActiveRecord::StatementInvalid
  end
end
