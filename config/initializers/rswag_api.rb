Rswag::Api.configure do |c|
  # Specify a root folder where Swagger JSON files are located
  # This is used by the Swagger middleware to serve requests for API descriptions
  # NOTE: If you're using rswag-specs to generate Swagger, you'll need to ensure
  # that it's configured to generate files in the same folder
  c.openapi_root = Rails.root.to_s + "/swagger"

  # swagger/v1/swagger.yaml ships servers: [{url: "{scheme}://{host}"}] so a
  # fresh checkout has something before anyone configures a real domain, but
  # that only works if swagger-ui substitutes the {scheme}/{host} variables
  # client-side — when it doesn't, "Try it out" fetches the literal string
  # "{scheme}://{host}/api/...", and Chrome reports exactly "Failed to fetch
  # ... URL scheme must be 'http' or 'https'" because "{scheme}" isn't one.
  # Replacing servers here with the real request's scheme/host removes the
  # client-side substitution from the picture entirely — this always answers
  # with a concrete URL matching wherever the docs are actually being viewed
  # from (dev, a tunnel, production).
  c.swagger_filter = lambda do |swagger, env|
    swagger["servers"] = [ { "url" => "#{env['rack.url_scheme']}://#{env['HTTP_HOST']}" } ]
  end
end
