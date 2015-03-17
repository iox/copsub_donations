class HoboMigration1 < ActiveRecord::Migration
  def self.up
    create_table :donations do |t|
      t.decimal  :amount, :precision => 8, :scale => 2
      t.decimal  :amount_in_dkk, :precision => 8, :scale => 2
      t.string   :currency
      t.time     :donated_at
      t.string   :bank_reference
      t.string   :email
      t.datetime :created_at
      t.datetime :updated_at
    end
  end

  def self.down
    drop_table :donations
  end
end
