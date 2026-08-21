module Api
  class BaseController < ActionController::API
    # Every endpoint here is public and unauthenticated, and some of them spend
    # the owner's Spotify quota on the caller's behalf. A burst would push the
    # whole app into a 429 at Spotify, which also stalls the sync job — and
    # since Spotify only keeps the last 50 plays, a stalled sync loses history
    # for good. The cap is what keeps a public route from costing us that.
    rate_limit to: 60, within: 1.minute,
               with: -> { render json: { error: "Too many requests" }, status: :too_many_requests }
  end
end
