class CreateLyrics < ActiveRecord::Migration[8.1]
  def change
    create_table :lyrics do |t|
      t.string :spotify_track_id, null: false
      t.text :plain_lyrics
      t.text :synced_lyrics
      t.boolean :instrumental, null: false, default: false
      t.datetime :matched_at

      t.timestamps
    end
    add_index :lyrics, :spotify_track_id, unique: true
  end
end
