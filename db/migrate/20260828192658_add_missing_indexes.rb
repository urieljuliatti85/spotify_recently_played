class AddMissingIndexes < ActiveRecord::Migration[8.1]
  def change
    # Api::AlbumsController#discogs queries by this column on every album page
    # load; the table grows with the size of the Discogs collection.
    add_index :discogs_matches, :spotify_album_id

    # The uniqueness validation on SpotifyAccount only ever ran at the Rails
    # level — nothing stopped two concurrent OAuth callbacks (an owner
    # reconnecting while a friend claims an invite, say) from both passing it
    # and writing duplicate rows for the same Spotify user.
    add_index :spotify_accounts, :spotify_user_id, unique: true
  end
end
