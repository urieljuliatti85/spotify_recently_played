class CreatePlays < ActiveRecord::Migration[8.1]
  def change
    create_table :plays do |t|
      t.references :track, null: false, foreign_key: true
      t.datetime   :played_at, null: false
      t.string     :context_type
      t.string     :context_url

      t.timestamps
    end

    # Spotify identifies a play event by its timestamp, so this is our idempotency key.
    add_index :plays, :played_at, unique: true
    add_index :plays, [ :played_at, :track_id ]
  end
end
