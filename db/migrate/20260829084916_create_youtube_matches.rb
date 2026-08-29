class CreateYoutubeMatches < ActiveRecord::Migration[8.1]
  def change
    create_table :youtube_matches do |t|
      t.string :spotify_track_id, null: false
      t.string :video_id
      t.datetime :matched_at

      t.timestamps
    end
    add_index :youtube_matches, :spotify_track_id, unique: true
  end
end
