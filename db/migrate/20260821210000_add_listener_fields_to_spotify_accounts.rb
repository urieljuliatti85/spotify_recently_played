# Friends can link their own account now, so a row is no longer "the" account —
# it is one listener among several, and the feed has to be able to name them.
class AddListenerFieldsToSpotifyAccounts < ActiveRecord::Migration[8.1]
  def up
    add_column :spotify_accounts, :owner, :boolean, default: false, null: false
    # A listener can be hidden from the public feed without unlinking, which is
    # what someone gets to ask for before their history goes on a public page.
    add_column :spotify_accounts, :visible, :boolean, default: true, null: false
    add_column :spotify_accounts, :avatar_url, :string

    # Whatever was linked before friends existed is the site's owner.
    accounts = Class.new(ActiveRecord::Base) { self.table_name = "spotify_accounts" }
    accounts.order(:id).first&.update_columns(owner: true)

    add_index :spotify_accounts, :owner
  end

  def down
    remove_index :spotify_accounts, :owner
    remove_column :spotify_accounts, :avatar_url
    remove_column :spotify_accounts, :visible
    remove_column :spotify_accounts, :owner
  end
end
