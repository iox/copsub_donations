# encoding: UTF-8
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 20160529063441) do

  create_table "categories", force: true do |t|
    t.string   "name"
    t.boolean  "default",    default: false
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "donations", force: true do |t|
    t.decimal  "amount",                precision: 8, scale: 2
    t.decimal  "amount_in_dkk",         precision: 8, scale: 2
    t.string   "currency"
    t.datetime "donated_at"
    t.string   "bank_reference"
    t.string   "email"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer  "seamless_donation_id"
    t.string   "donation_method"
    t.integer  "wordpress_user_id"
    t.boolean  "user_assigned",                                 default: false
    t.boolean  "other_income",                                  default: false
    t.integer  "category_id"
    t.string   "paypal_transaction_id"
    t.integer  "donor_id"
  end

  add_index "donations", ["category_id"], name: "index_donations_on_category_id", using: :btree
  add_index "donations", ["donor_id"], name: "index_donations_on_donor_id", using: :btree

  create_table "donors", force: true do |t|
    t.integer  "wordpress_id"
    t.string   "user_email"
    t.string   "user_login"
    t.string   "display_name"
    t.text     "user_adress"
    t.string   "city"
    t.string   "country"
    t.string   "paymentid"
    t.string   "paypalid"
    t.string   "user_phone"
    t.integer  "donated_last_year_in_dkk"
    t.string   "role"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "alternativeid"
    t.date     "first_donated_at"
    t.string   "mailchimp_status",         default: "not_present"
    t.text     "notes"
    t.integer  "donated_total"
    t.date     "last_donated_at"
    t.string   "donation_method"
  end

  create_table "saved_searches", force: true do |t|
    t.string   "name"
    t.text     "path"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "users", force: true do |t|
    t.string   "crypted_password",          limit: 40
    t.string   "salt",                      limit: 40
    t.string   "remember_token"
    t.datetime "remember_token_expires_at"
    t.string   "name"
    t.string   "email_address"
    t.boolean  "administrator",                        default: false
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "state",                                default: "invited"
    t.datetime "key_timestamp"
  end

  add_index "users", ["state"], name: "index_users_on_state", using: :btree

end
