module Api
  class BaseController < ActionController::API
    # Every endpoint here is public and unauthenticated, and some of them spend
    # the owner's Spotify quota on the caller's behalf. A burst would push the
    # whole app into a 429 at Spotify, which also stalls the sync job — and
    # since Spotify only keeps the last 50 plays, a stalled sync loses history
    # for good. The cap is what keeps a public route from costing us that.
    rate_limit to: 60, within: 1.minute,
               with: -> { render json: { error: "Too many requests" }, status: :too_many_requests }

    # Every action here that hits Spotify repeats the same two outcomes for an
    # unlinked account or an opaque API failure; only a 403's scope-specific
    # message and a resource's 404 message are worth writing out per action.
    #
    # Rails checks rescue_from handlers in reverse declaration order, so the
    # more specific NotConnectedError has to be declared after Error — first
    # in the search order — or the generic handler catches it first.
    rescue_from Spotify::Error do |e|
      render json: { error: e.message }, status: :bad_gateway
    end

    rescue_from Spotify::NotConnectedError do |e|
      render json: { error: e.message }, status: :service_unavailable
    end
  end
end
