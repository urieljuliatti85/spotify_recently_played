# rswag-ui's own Rack::Static subclass sets a Content-Security-Policy header
# (permissive, to allow its inline bootstrap script) but under the
# capitalized "Content-Security-Policy" key, which is not what Rack 3 /
# Rails 8's own CSP middleware checks for (lowercase) — so both headers
# ship, and the strict app-wide policy in content_security_policy.rb (no
# unsafe-inline, self-only script-src) still blocks the swagger-ui page's
# inline bootstrap script even though rswag "already handled" it. Replacing
# the header under the lowercase key here is what makes Rails' own
# middleware recognize a policy is already present and skip adding its
# stricter one.
class SwaggerCsp
  POLICY = "default-src 'self'; " \
    "img-src 'self' data: https://validator.swagger.io; " \
    "font-src 'self' https://fonts.gstatic.com; " \
    "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; " \
    "script-src 'self' 'unsafe-inline'".freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)
    headers.delete("Content-Security-Policy")
    headers["content-security-policy"] = POLICY
    [ status, headers, body ]
  end
end
