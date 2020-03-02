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

ActiveRecord::Schema.define(version: 2020_02_28_210306) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "customers", force: :cascade do |t|
    t.integer "desk_id"
    t.string "email"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "desk_cases", force: :cascade do |t|
    t.string "email"
    t.string "subject"
    t.text "body"
    t.integer "desk_id"
    t.integer "freshdesk_id"
    t.datetime "case_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "failed"
  end

  create_table "desk_messages", force: :cascade do |t|
    t.text "body"
    t.bigint "desk_case_id"
    t.string "kind"
    t.datetime "message_created_at"
    t.boolean "copied_to_freshdesk", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "from"
    t.index ["desk_case_id"], name: "index_desk_messages_on_desk_case_id"
  end

  create_table "hyperstack_connections", force: :cascade do |t|
    t.string "channel"
    t.string "session"
    t.datetime "created_at"
    t.datetime "expires_at"
    t.datetime "refresh_at"
  end

  create_table "hyperstack_queued_messages", force: :cascade do |t|
    t.text "data"
    t.integer "connection_id"
  end

  create_table "stats", force: :cascade do |t|
    t.string "stat"
    t.text "value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "desk_messages", "desk_cases"
end
