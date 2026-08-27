# An earlier, abandoned pass at this feature mirrored the shelf's releases into
# a local `discogs_releases` table. Its migration is not in the repository, but
# it did run against the development database and left the (empty) table behind,
# so a schema dump picks up a table nothing creates and nothing reads. The
# integration reads the shelf's API instead and caches only the Spotify match.
class DropOrphanedDiscogsReleases < ActiveRecord::Migration[8.1]
  def up
    drop_table :discogs_releases, if_exists: true
  end

  def down
    # Nothing to restore: the table was empty and no code ever read it.
  end
end
