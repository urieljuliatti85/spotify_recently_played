module Spotify
  # Pulls the account's recent plays and stores anything we haven't seen.
  class RecentlyPlayedSync
    Result = Struct.new(:imported, :latest_played_at, keyword_init: true)

    def self.call(...) = new(...).call

    def initialize(account = SpotifyAccount.current, client: nil)
      raise NotConnectedError, "No Spotify account linked yet" if account.nil?

      @account = account
      @client = client || Client.new(account)
    end

    def call
      items = Array(client.recently_played(after: account.last_played_at)&.fetch("items", nil))
      played_ats = items.map { |item| Time.parse(item["played_at"]) }

      # One lookup for the whole page rather than one per item: the ordinary
      # poll brings back plays we already have and imports none of them.
      stored = stored_played_ats(played_ats)

      imported = items.zip(played_ats).sum do |item, played_at|
        key = key_for(played_at)
        next 0 if stored.include?(key)

        # Marked before the insert, so a payload that somehow lists the same
        # instant twice still imports it once — the per-item `exists?` this
        # replaced covered that case by accident.
        stored << key
        import(item, played_at)
      end

      fill_new_artist_images if imported.positive?

      account.update!(
        last_synced_at: Time.current,
        last_played_at: [ account.last_played_at, played_ats.max ].compact.max
      )

      Result.new(imported:, latest_played_at: account.last_played_at)
    end

    private

    attr_reader :account, :client

    def import(item, played_at)
      track = Track.upsert_from_spotify!(item["track"])
      Play.create!(
        track: track,
        played_at: played_at,
        context_type: item.dig("context", "type"),
        context_url: item.dig("context", "external_urls", "spotify")
      )
      1
    rescue ActiveRecord::RecordNotUnique
      # A concurrent sync already stored this play.
      0
    end

    # Artists arrive from the plays feed without photos. This costs one extra
    # request while there are new ones and nothing once they all have a photo,
    # and a failure here must never cost us the plays just imported.
    def fill_new_artist_images
      ArtistBackfill.new(account, client: client).fill_images(max_batches: 1)
    rescue Spotify::Error
      0
    end

    # A play is identified by the exact instant it happened, so both sides are
    # compared as the same UTC string: what comes back from the database is not
    # the same class as what was just parsed out of the payload, and the two
    # only agree on the instant, not on `eql?`.
    def stored_played_ats(played_ats)
      return Set.new if played_ats.empty?

      Play.where(played_at: played_ats).pluck(:played_at).map { |stored| key_for(stored) }.to_set
    end

    def key_for(time)
      time.getutc.iso8601(3)
    end
  end
end
