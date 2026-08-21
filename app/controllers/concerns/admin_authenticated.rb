# Guards the owner-only routes (linking the Spotify account, forcing a sync).
# The public site never touches these.
module AdminAuthenticated
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_admin!
  end

  private

  def authenticate_admin!
    password = ENV["ADMIN_PASSWORD"].presence

    if password.nil?
      # Convenience for local development, and only from the machine itself:
      # a dev server bound to 0.0.0.0 or shared through a tunnel (which is how
      # the Spotify callback usually gets tested) would otherwise hand these
      # routes to anyone who can reach it.
      return if Rails.env.development? && request.local?

      render plain: "Set ADMIN_PASSWORD to use the owner-only routes.", status: :service_unavailable
      return
    end

    authenticate_or_request_with_http_basic("Owner") do |_user, given|
      ActiveSupport::SecurityUtils.secure_compare(given.to_s, password)
    end
  end
end
