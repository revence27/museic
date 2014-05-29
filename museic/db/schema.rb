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

ActiveRecord::Schema.define(version: 20140529133455) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "album_arts", force: true do |t|
    t.text     "sha1_sig"
    t.text     "content_type"
    t.binary   "rawdata"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "museic_songs", force: true do |t|
    t.text     "path"
    t.text     "title"
    t.text     "artist"
    t.text     "album"
    t.text     "sleeve_sha1"
    t.integer  "seconds"
    t.integer  "year"
    t.datetime "last_play"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "plays", force: true do |t|
    t.text     "path"
    t.datetime "recent"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

end
