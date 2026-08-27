class CreateDiscogsMatches < ActiveRecord::Migration[8.1]
  def change
    create_table :discogs_matches do |t|
      t.integer :discogs_id, null: false
      t.string :spotify_album_id
      t.integer :track_count, null: false, default: 0
      t.integer :playable_count, null: false, default: 0
      t.json :payload
      t.datetime :matched_at

      t.timestamps
    end

    add_index :discogs_matches, :discogs_id, unique: true
  end
end
