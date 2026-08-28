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

ActiveRecord::Schema[8.1].define(version: 2026_08_28_192658) do
  create_table "artists", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "image_url"
    t.string "name", null: false
    t.string "spotify_id", null: false
    t.string "spotify_url"
    t.datetime "updated_at", null: false
    t.index ["spotify_id"], name: "index_artists_on_spotify_id", unique: true
  end

  create_table "discogs_matches", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "discogs_id", null: false
    t.datetime "matched_at"
    t.json "payload"
    t.integer "playable_count", default: 0, null: false
    t.string "spotify_album_id"
    t.integer "track_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["discogs_id"], name: "index_discogs_matches_on_discogs_id", unique: true
    t.index ["spotify_album_id"], name: "index_discogs_matches_on_spotify_album_id"
  end

  create_table "invites", force: :cascade do |t|
    t.datetime "claimed_at"
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "label"
    t.integer "spotify_account_id"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["spotify_account_id"], name: "index_invites_on_spotify_account_id"
    t.index ["token_digest"], name: "index_invites_on_token_digest", unique: true
  end

  create_table "plays", force: :cascade do |t|
    t.string "context_type"
    t.string "context_url"
    t.datetime "created_at", null: false
    t.datetime "played_at", null: false
    t.integer "spotify_account_id", null: false
    t.integer "track_id", null: false
    t.datetime "updated_at", null: false
    t.index ["played_at", "track_id"], name: "index_plays_on_played_at_and_track_id"
    t.index ["played_at"], name: "index_plays_on_played_at"
    t.index ["spotify_account_id", "played_at"], name: "index_plays_on_spotify_account_id_and_played_at", unique: true
    t.index ["track_id"], name: "index_plays_on_track_id"
  end

  create_table "spotify_accounts", force: :cascade do |t|
    t.text "access_token"
    t.string "avatar_url"
    t.datetime "created_at", null: false
    t.string "display_name"
    t.datetime "last_played_at"
    t.datetime "last_synced_at"
    t.boolean "owner", default: false, null: false
    t.text "refresh_token"
    t.string "scope"
    t.string "spotify_user_id"
    t.datetime "token_expires_at"
    t.datetime "updated_at", null: false
    t.boolean "visible", default: true, null: false
    t.index ["owner"], name: "index_spotify_accounts_on_owner"
    t.index ["spotify_user_id"], name: "index_spotify_accounts_on_spotify_user_id", unique: true
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
    t.string "spotify_album_id"
    t.string "spotify_id", null: false
    t.string "spotify_url"
    t.datetime "updated_at", null: false
    t.index ["spotify_album_id"], name: "index_tracks_on_spotify_album_id"
    t.index ["spotify_id"], name: "index_tracks_on_spotify_id", unique: true
  end

  add_foreign_key "invites", "spotify_accounts"
  add_foreign_key "plays", "spotify_accounts"
  add_foreign_key "plays", "tracks"
  add_foreign_key "track_artists", "artists"
  add_foreign_key "track_artists", "tracks"
end
