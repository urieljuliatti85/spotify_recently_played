# A friend needs a way in that is not the owner's password. An invite is a
# single-use, expiring link: the raw token is shown once when it is issued and
# only its digest is stored, so a database copy cannot be replayed into an
# account link.
class CreateInvites < ActiveRecord::Migration[8.1]
  def change
    create_table :invites do |t|
      t.string :token_digest, null: false
      t.string :label
      t.datetime :expires_at, null: false
      t.datetime :claimed_at
      t.references :spotify_account, foreign_key: true, index: true
      t.timestamps
    end

    add_index :invites, :token_digest, unique: true
  end
end
