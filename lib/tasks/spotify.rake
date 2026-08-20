namespace :spotify do
  desc "Fetch the latest plays from Spotify into the local database"
  task sync: :environment do
    result = Spotify::RecentlyPlayedSync.call
    puts "Imported #{result.imported} play(s). Latest: #{result.latest_played_at || 'none'}."
  rescue Spotify::NotConnectedError
    abort "No Spotify account linked yet. Start the server and visit /spotify/connect."
  end
end
