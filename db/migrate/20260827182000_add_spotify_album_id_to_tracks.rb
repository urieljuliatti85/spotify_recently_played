class AddSpotifyAlbumIdToTracks < ActiveRecord::Migration[8.1]
  def change
    add_column :tracks, :spotify_album_id, :string
    add_index :tracks, :spotify_album_id
  end
end
