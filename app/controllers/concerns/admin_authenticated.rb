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
      # Convenience for local development; production must set a password.
      return if Rails.env.development?

      render plain: "Set ADMIN_PASSWORD to use the owner-only routes.", status: :service_unavailable
      return
    end

    authenticate_or_request_with_http_basic("Owner") do |_user, given|
      ActiveSupport::SecurityUtils.secure_compare(given.to_s, password)
    end
  end
end
