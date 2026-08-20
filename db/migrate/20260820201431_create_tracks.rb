class CreateTracks < ActiveRecord::Migration[8.1]
  def change
    create_table :tracks do |t|
      t.string  :spotify_id,      null: false
      t.string  :name,            null: false
      t.string  :artist_names,    null: false, default: ""
      t.string  :album_name
      t.string  :album_image_url
      t.string  :spotify_url
      t.integer :duration_ms
      t.boolean :explicit,        null: false, default: false

      t.timestamps
    end

    add_index :tracks, :spotify_id, unique: true
  end
end
