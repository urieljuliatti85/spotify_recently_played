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
  desc "Issue a single-use invite link so a friend can add their own account"
  task :invite, [ :spotify_user_id ] => :environment do |_task, args|
    abort "Usage: bin/rails \"spotify:invite[<spotify_user_id>]\" — find it at " \
          "open.spotify.com/user/<id> on the friend's profile page." if args[:spotify_user_id].blank?

    invite = Invite.issue!(spotify_user_id: args[:spotify_user_id])
    origin = URI.parse(Spotify.redirect_uri)

    puts "Invite ##{invite.id} for #{invite.spotify_user_id}"
    puts "#{origin.scheme}://#{origin.authority}/spotify/join/#{invite.token}"
    puts "Single use, expires #{invite.expires_at.iso8601}."
    puts "Only that Spotify account can claim it — the callback checks it against #{invite.spotify_user_id}."
    puts
    puts "Heads up: whatever they play lands on the public feed. Say so before sending it."
  end

  desc "List every invite and what became of it"
  task invites: :environment do
    invites = Invite.order(created_at: :desc)
    next puts("No invites yet. Run bin/rails 'spotify:invite[<spotify_user_id>]'.") if invites.empty?

    invites.each do |invite|
      state = if invite.claimed?
                "claimed by #{invite.spotify_account&.display_name || "a deleted account"}"
      elsif invite.expired?
                "expired"
      else
                "open until #{invite.expires_at.iso8601}"
      end

      puts "##{invite.id} #{invite.spotify_user_id} — #{state}"
    end
  end

  desc "Revoke an unclaimed invite by id"
  task :revoke_invite, [ :id ] => :environment do |_task, args|
    invite = Invite.find_by(id: args[:id])
    abort "No invite ##{args[:id]}." if invite.nil?

    invite.destroy
    puts "Invite ##{args[:id]} revoked."
  end

  desc "List the listeners on the feed"
  task listeners: :environment do
    SpotifyAccount.order(owner: :desc, id: :asc).each do |account|
      flags = [ account.owner? ? "owner" : "friend",
                account.visible? ? "visible" : "hidden",
                account.refresh_token.present? ? "linked" : "no token" ]
      puts "##{account.id} #{account.display_name} [#{flags.join(", ")}] — #{account.plays.count} play(s)"
    end
  end

  desc "Hide a listener from the public feed without unlinking them"
  task :hide, [ :id ] => :environment do |_task, args|
    account = SpotifyAccount.find_by(id: args[:id])
    abort "No listener ##{args[:id]}. Run bin/rails spotify:listeners." if account.nil?

    account.update!(visible: false)
    puts "#{account.display_name} is off the public feed. Their plays are kept and still sync."
  end

  desc "Put a hidden listener back on the public feed"
  task :show, [ :id ] => :environment do |_task, args|
    account = SpotifyAccount.find_by(id: args[:id])
    abort "No listener ##{args[:id]}. Run bin/rails spotify:listeners." if account.nil?

    account.update!(visible: true)
    puts "#{account.display_name} is back on the public feed."
  end

  desc "Unlink a listener and delete their history"
  task :unlink, [ :id ] => :environment do |_task, args|
    account = SpotifyAccount.find_by(id: args[:id])
    abort "No listener ##{args[:id]}. Run bin/rails spotify:listeners." if account.nil?

    count = account.plays.count
    account.destroy
    puts "#{account.display_name} unlinked; #{count} play(s) deleted."
  end
end
