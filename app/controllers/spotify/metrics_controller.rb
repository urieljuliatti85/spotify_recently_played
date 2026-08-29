module Spotify
  # Owner-only JSON view of the app's own Prometheus series (see
  # Spotify::MetricsSnapshot and config/initializers/yabeda.rb) for the
  # dashboard at ?view=metrics — the raw exposition format at GET /metrics
  # is what an actual Prometheus server scrapes, this is what a browser
  # renders as charts.
  class MetricsController < ApplicationController
    include AdminAuthenticated

    def show
      render json: MetricsSnapshot.call
    end
  end
end
