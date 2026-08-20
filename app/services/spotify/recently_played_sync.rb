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
      imported = items.sum { |item| import(item) }

      account.update!(
        last_synced_at: Time.current,
        last_played_at: [ account.last_played_at, latest_played_at(items) ].compact.max
      )

      Result.new(imported:, latest_played_at: account.last_played_at)
    end

    private

    attr_reader :account, :client

    def import(item)
      played_at = Time.parse(item["played_at"])
      return 0 if Play.exists?(played_at: played_at)

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

    def latest_played_at(items)
      items.filter_map { |item| Time.parse(item["played_at"]) }.max
    end
  end
end
