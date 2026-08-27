namespace :discogs do
  desc "Check that the discogs_shelf app is configured and answering"
  task check: :environment do
    abort "DISCOGS_SHELF_URL is not set. Add it to .env." unless DiscogsShelf.configured?

    profile = DiscogsShelf::Client.new.profile
    puts "#{DiscogsShelf.base_url} → #{profile["username"]}: " \
         "#{profile.dig("stats", "collection_count")} in the collection, " \
         "#{profile.dig("stats", "wantlist_count")} on the wantlist."
    puts "Spotify market: #{Spotify.market || "unset — playability will read as unknown"}"
  rescue DiscogsShelf::Error => e
    abort e.message
  end

  desc "Match the whole shelf against Spotify up front, so the grid is badged before anyone opens a record"
  task match: :environment do
    shelf = DiscogsShelf::Client.new
    items = shelf.items("collection", per_page: 100)["items"]
    puts "#{items.size} record(s) to check."

    matched = 0
    items.each do |item|
      release = shelf.release(item["discogs_id"])
      result = DiscogsMatch.resolve(release)
      matched += 1 if result.playable_count.positive?

      puts format("  %-30s %-40s %s", item["artist"].to_s.truncate(30), item["title"].to_s.truncate(40),
                  "#{result.playable_count}/#{result.track_count}")
    rescue Spotify::RateLimitedError => e
      # Spotify said to back off, and there are still records to go. Stopping
      # keeps the tab working for what has already been matched; a rerun picks
      # up where this left off, since matched rows are not recomputed.
      abort "Rate limited by Spotify after #{matched} record(s). Retry in #{e.retry_after || 30}s."
    rescue DiscogsShelf::Error, Spotify::Error => e
      puts "  #{item["title"]}: #{e.message}"
    end

    puts "#{matched} of #{items.size} record(s) have something playable on Spotify."
  rescue DiscogsShelf::Error => e
    abort e.message
  rescue Spotify::NotConnectedError
    abort "No Spotify account linked yet. Start the server and visit /spotify/connect."
  end
end
