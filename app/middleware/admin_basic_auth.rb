# Gates a mounted Rack app the same way AdminAuthenticated gates the
# owner-only controller routes — /api-docs and /metrics are both engines/apps
# with no controller of their own to include that concern into, so the same
# ADMIN_PASSWORD/dev-local-bypass rule is reimplemented here at the Rack
# layer instead. Purely the auth gate; see SwaggerCsp for the header rewrite
# rswag's own mount additionally needs.
class AdminBasicAuth
  def initialize(app)
    @app = app
  end

  def call(env)
    request = ActionDispatch::Request.new(env)
    password = ENV["ADMIN_PASSWORD"].presence

    if password.nil?
      return @app.call(env) if Rails.env.development? && request.local?

      return [ 503, { "content-type" => "text/plain" }, [ "Set ADMIN_PASSWORD to use the owner-only routes." ] ]
    end

    Rack::Auth::Basic.new(@app, "Owner") do |_user, given|
      ActiveSupport::SecurityUtils.secure_compare(given.to_s, password)
    end.call(env)
  end
end
