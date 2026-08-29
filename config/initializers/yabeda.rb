# yabeda-rails (see Gemfile) wires up the generic rails_requests_total /
# rails_request_duration series on its own. What it can't see is the thing
# that actually constrains this app operationally: Spotify request volume
# (Api::BaseController's 60/min limit exists because a burst there stalls the
# sync and loses history permanently, per CLAUDE.md) and whether the
# per-listener sync job is keeping up. Those two groups are defined here and
# recorded from Spotify::Client and SyncRecentlyPlayedJob.
Yabeda.configure do
  group :spotify

  counter   :requests_total, comment: "Requests made to the Spotify Web API.",
                             tags: %i[endpoint status]
  histogram :request_duration, comment: "Spotify Web API response latency.",
                               unit: :seconds,
                               buckets: [ 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 30 ],
                               tags: %i[endpoint]

  group :spotify_sync

  counter :runs_total, comment: "SyncRecentlyPlayedJob outcomes.",
                       tags: %i[listener outcome]
  counter :plays_imported_total, comment: "Plays imported by SyncRecentlyPlayedJob.",
                                 tags: %i[listener]
end
