# Gates /api-docs the same way AdminAuthenticated gates the owner-only
# controller routes. The rswag engines are mounted Rack apps with no
# controller of their own to include that concern into, so the same
# ADMIN_PASSWORD/dev-local-bypass rule is reimplemented here at the Rack
# layer instead.
#
# Also overwrites the response's Content-Security-Policy. rswag-ui's own
# Rack::Static subclass sets one (permissive, to allow its inline bootstrap
# script) but under the capitalized "Content-Security-Policy" key, which is
# not what Rack 3 / Rails 8's own CSP middleware checks for (lowercase) — so
# both headers ship, and the strict app-wide policy in
# content_security_policy.rb (no unsafe-inline, self-only script-src) still
# blocks the swagger-ui page's inline bootstrap script even though rswag
# "already handled" it. Replacing the header under the lowercase key here is
# what makes Rails' own middleware recognize a policy is already present and
# skip adding its stricter one.
class AdminBasicAuth
  SWAGGER_CSP = "default-src 'self'; " \
    "img-src 'self' data: https://validator.swagger.io; " \
    "font-src 'self' https://fonts.gstatic.com; " \
    "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; " \
    "script-src 'self' 'unsafe-inline'".freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    request = ActionDispatch::Request.new(env)
    password = ENV["ADMIN_PASSWORD"].presence

    if password.nil?
      return with_swagger_csp(@app.call(env)) if Rails.env.development? && request.local?

      return [ 503, { "content-type" => "text/plain" }, [ "Set ADMIN_PASSWORD to use the owner-only routes." ] ]
    end

    response = Rack::Auth::Basic.new(@app, "Owner") do |_user, given|
      ActiveSupport::SecurityUtils.secure_compare(given.to_s, password)
    end.call(env)

    with_swagger_csp(response)
  end

  private

  def with_swagger_csp(response)
    status, headers, body = response
    headers.delete("Content-Security-Policy")
    headers["content-security-policy"] = SWAGGER_CSP
    [ status, headers, body ]
  end
end
