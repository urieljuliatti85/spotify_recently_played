namespace :spotify do
  desc "Fetch the latest plays from Spotify into the local database"
  task sync: :environment do
    result = Spotify::RecentlyPlayedSync.call
    puts "Imported #{result.imported} play(s). Latest: #{result.latest_played_at || 'none'}."
  rescue Spotify::NotConnectedError
    abort "No Spotify account linked yet. Start the server and visit /spotify/connect."
  end

  desc "Recover per-artist credits for tracks stored before artists were modelled"
  task backfill_artists: :environment do
    result = Spotify::ArtistBackfill.call
    puts "Linked #{result.linked_tracks} track(s); fetched #{result.imaged_artists} artist photo(s)."
  rescue Spotify::NotConnectedError
    abort "No Spotify account linked yet. Start the server and visit /spotify/connect."
  end
end
