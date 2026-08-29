module Spotify
  # Public JSON view of the app's own Prometheus series (see
  # Spotify::MetricsSnapshot and config/initializers/yabeda.rb) for the
  # dashboard at ?view=metrics — the raw exposition format at GET /metrics
  # is what an actual Prometheus server scrapes (still owner-gated, see
  # AdminBasicAuth in config/routes.rb), this is what a browser renders as
  # charts, and it's deliberately open: request counts, latency and sync
  # outcomes are operational detail, not anything private about a listener.
  class MetricsController < ApplicationController
    def show
      render json: MetricsSnapshot.call
    end
  end
end
