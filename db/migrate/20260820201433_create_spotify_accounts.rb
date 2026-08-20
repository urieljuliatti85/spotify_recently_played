class CreateSpotifyAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :spotify_accounts do |t|
      t.string   :spotify_user_id
      t.string   :display_name
      t.text     :access_token
      t.text     :refresh_token
      t.datetime :token_expires_at
      t.string   :scope
      t.datetime :last_synced_at
      t.datetime :last_played_at

      t.timestamps
    end
  end
end
