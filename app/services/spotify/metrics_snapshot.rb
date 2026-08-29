module Spotify
  # Turns the live Prometheus registry (the same numbers /metrics exposes as
  # text — see config/initializers/yabeda.rb for what's actually defined)
  # into JSON shaped for the owner-only dashboard, so the frontend never has
  # to parse the exposition format itself.
  class MetricsSnapshot
    def self.call = new.call

    def call
      Yabeda.collect!

      {
        spotify_requests: counter(:spotify_requests_total, %i[endpoint status]),
        spotify_latency: histogram(:spotify_request_duration_seconds, %i[endpoint]),
        sync_runs: counter(:spotify_sync_runs_total, %i[listener outcome]),
        sync_plays_imported: counter(:spotify_sync_plays_imported_total, %i[listener]),
        rails_requests: counter(:rails_requests_total, %i[controller action status]),
        rails_latency: histogram(:rails_request_duration_seconds, %i[controller action])
      }
    end

    private

    # A metric that was never touched (no request has hit that code path yet)
    # is not registered at all — Yabeda only creates the underlying
    # prometheus-client object on first increment/measure — so a missing name
    # means "nothing happened" rather than an error.
    def registered(name)
      Yabeda::Prometheus.registry.get(name)
    end

    def counter(name, label_keys)
      metric = registered(name)
      return [] unless metric

      metric.values.map { |labels, value| labels.slice(*label_keys).merge(count: value.to_i) }
    end

    def histogram(name, label_keys)
      metric = registered(name)
      return [] unless metric

      metric.values.filter_map do |labels, buckets|
        count = buckets["+Inf"].to_i
        next nil if count.zero?

        labels.slice(*label_keys).merge(count: count, avg_seconds: (buckets["sum"] / count).round(4))
      end
    end
  end
end
