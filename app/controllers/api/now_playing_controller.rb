module Api
  # The public "now playing" badge — meant to be hotlinked from a GitHub
  # README or personal site. Reads only the local mirror, so unlike almost
  # everything else under /api this never touches Spotify: a viral embed
  # can't spend anyone's quota or stall the sync.
  class NowPlayingController < BaseController
    def show
      play = Play.on_the_feed
                 .by_listener(params[:listener])
                 .recent
                 .includes(:track)
                 .first

      # Short cache: long enough that a burst of readers hitting the same
      # README only costs one render, short enough the badge stays honestly
      # "now playing" instead of going stale for minutes.
      response.headers["Cache-Control"] = "public, max-age=30"
      render plain: NowPlayingCard.new(play).to_svg, content_type: "image/svg+xml"
    end
  end
end
