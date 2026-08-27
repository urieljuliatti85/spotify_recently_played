module DiscogsShelf
  # The Discogs collection lives in the sibling `discogs_shelf` app, which
  # already mirrors Discogs into its own SQLite and serves it as JSON. This app
  # reads that API rather than talking to Discogs itself: the sync, the rate
  # limiting and the release cache are solved problems over there, and
  # duplicating them here would mean a second Discogs token and a second mirror
  # of the same collection.
  class Error < StandardError
    attr_reader :status

    def initialize(message, status: nil)
      @status = status
      super(message)
    end
  end

  # DISCOGS_SHELF_URL is unset — the tab has nothing to point at.
  class NotConfiguredError < Error; end

  # Configured, but the shelf did not answer (not running, wrong port).
  class UnreachableError < Error; end

  class << self
    def base_url
      ENV["DISCOGS_SHELF_URL"].presence
    end

    def configured?
      base_url.present?
    end
  end
end
