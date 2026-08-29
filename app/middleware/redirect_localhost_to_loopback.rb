# Development only (see config/environments/development.rb). Spotify's
# redirect_uri match is an exact string, and "localhost" and "127.0.0.1" are
# different strings to it even though they're the same machine. The
# spotify/connect and spotify/join flows are immune — SPOTIFY_REDIRECT_URI is
# a fixed configured value — but /listen/callback's redirect_uri deliberately
# mirrors whatever host actually served the page, so it works against any
# production domain with nothing to configure. That same flexibility means
# typing "localhost" instead of "127.0.0.1" in the address bar quietly sends
# Spotify the wrong redirect_uri, and the only symptom is "redirect_uri: Not
# matching configuration" with no clue why. Bouncing "localhost" to the
# loopback IP before any view renders is what keeps that from happening.
class RedirectLocalhostToLoopback
  def initialize(app)
    @app = app
  end

  def call(env)
    request = ActionDispatch::Request.new(env)

    return @app.call(env) unless request.host == "localhost"

    uri = URI.parse(request.original_url)
    uri.host = "127.0.0.1"
    [ 302, { "Location" => uri.to_s, "content-type" => "text/plain" }, [ "Redirecting to #{uri}" ] ]
  end
end
