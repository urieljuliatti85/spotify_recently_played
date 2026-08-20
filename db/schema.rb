# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_20_223555) do
  create_table "artists", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "image_url"
    t.string "name", null: false
    t.string "spotify_id", null: false
    t.string "spotify_url"
    t.datetime "updated_at", null: false
    t.index ["spotify_id"], name: "index_artists_on_spotify_id", unique: true
  end

  create_table "plays", force: :cascade do |t|
    t.string "context_type"
    t.string "context_url"
    t.datetime "created_at", null: false
    t.datetime "played_at", null: false
    t.integer "track_id", null: false
    t.datetime "updated_at", null: false
    t.index ["played_at", "track_id"], name: "index_plays_on_played_at_and_track_id"
    t.index ["played_at"], name: "index_plays_on_played_at", unique: true
    t.index ["track_id"], name: "index_plays_on_track_id"
  end

  create_table "spotify_accounts", force: :cascade do |t|
    t.text "access_token"
    t.datetime "created_at", null: false
    t.string "display_name"
    t.datetime "last_played_at"
    t.datetime "last_synced_at"
    t.text "refresh_token"
    t.string "scope"
    t.string "spotify_user_id"
    t.datetime "token_expires_at"
    t.datetime "updated_at", null: false
  end

  create_table "track_artists", force: :cascade do |t|
    t.integer "artist_id", null: false
    t.datetime "created_at", null: false
    t.integer "position", default: 0, null: false
    t.integer "track_id", null: false
    t.datetime "updated_at", null: false
    t.index ["artist_id"], name: "index_track_artists_on_artist_id"
    t.index ["track_id", "artist_id"], name: "index_track_artists_on_track_id_and_artist_id", unique: true
    t.index ["track_id", "position"], name: "index_track_artists_on_track_id_and_position"
    t.index ["track_id"], name: "index_track_artists_on_track_id"
  end

  create_table "tracks", force: :cascade do |t|
    t.string "album_image_url"
    t.string "album_name"
    t.string "artist_names", default: "", null: false
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.boolean "explicit", default: false, null: false
    t.string "name", null: false
    t.string "spotify_id", null: false
    t.string "spotify_url"
    t.datetime "updated_at", null: false
    t.index ["spotify_id"], name: "index_tracks_on_spotify_id", unique: true
  end

  add_foreign_key "plays", "tracks"
  add_foreign_key "track_artists", "artists"
  add_foreign_key "track_artists", "tracks"
end
