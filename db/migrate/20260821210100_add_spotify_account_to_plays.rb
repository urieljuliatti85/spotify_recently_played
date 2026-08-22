# A play belongs to whoever played it. The uniqueness that used to sit on
# `played_at` alone said "no two plays ever share an instant", which was only
# true while there was one listener — two people press play at the same second
# all the time.
class AddSpotifyAccountToPlays < ActiveRecord::Migration[8.1]
  def up
    add_reference :plays, :spotify_account, foreign_key: true, index: false

    plays = Class.new(ActiveRecord::Base) { self.table_name = "plays" }
    accounts = Class.new(ActiveRecord::Base) { self.table_name = "spotify_accounts" }

    if plays.where(spotify_account_id: nil).exists?
      # Unlinking an account used to leave its plays behind with nothing
      # pointing at them; those still need a listener to hang off.
      owner_id = accounts.order(:id).pick(:id) ||
                 accounts.create!(display_name: "Unknown listener", visible: true, owner: false,
                                  created_at: Time.current, updated_at: Time.current).id

      plays.where(spotify_account_id: nil).update_all(spotify_account_id: owner_id)
    end

    change_column_null :plays, :spotify_account_id, false

    remove_index :plays, column: :played_at
    add_index :plays, :played_at
    add_index :plays, [ :spotify_account_id, :played_at ], unique: true
  end

  def down
    remove_index :plays, column: [ :spotify_account_id, :played_at ]
    remove_index :plays, column: :played_at
    add_index :plays, :played_at, unique: true
    remove_reference :plays, :spotify_account, foreign_key: true
  end
end
