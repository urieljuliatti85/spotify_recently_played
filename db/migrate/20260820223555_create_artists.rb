class CreateArtists < ActiveRecord::Migration[8.1]
  def change
    create_table :artists do |t|
      t.string :spotify_id,  null: false
      t.string :name,        null: false
      t.string :spotify_url
      t.string :image_url

      t.timestamps
    end

    add_index :artists, :spotify_id, unique: true

    # Ordered join: Spotify returns a track's artists with the lead first, and
    # that order is what the UI credits.
    create_table :track_artists do |t|
      t.references :track,  null: false, foreign_key: true
      t.references :artist, null: false, foreign_key: true
      t.integer    :position, null: false, default: 0

      t.timestamps
    end

    add_index :track_artists, [ :track_id, :artist_id ], unique: true
    add_index :track_artists, [ :track_id, :position ]
  end
end
