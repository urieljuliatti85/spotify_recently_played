class RenameLabelToSpotifyUserIdOnInvites < ActiveRecord::Migration[8.1]
  def change
    # An invite now pins who may claim it (verified against Spotify's `/me`
    # at the callback) rather than just carrying a display label — see
    # Spotify::SessionsController#link_account.
    rename_column :invites, :label, :spotify_user_id
  end
end
