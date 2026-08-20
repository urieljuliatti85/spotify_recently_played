require "net/http"

module Spotify
  # Authorization Code flow: link the owner's account once, then keep a
  # refresh token so background syncs never need a browser again.
  module Authorization
    ACCOUNTS_HOST = "https://accounts.spotify.com".freeze

    class << self
      def authorize_url(state:)
        query = URI.encode_www_form(
          client_id: Spotify.client_id,
          response_type: "code",
          redirect_uri: Spotify.redirect_uri,
          scope: Spotify::SCOPES.join(" "),
          state: state,
          # Force the consent screen so switching accounts is possible.
          show_dialog: "true"
        )

        "#{ACCOUNTS_HOST}/authorize?#{query}"
      end

      def exchange_code(code)
        post_token(
          grant_type: "authorization_code",
          code: code,
          redirect_uri: Spotify.redirect_uri
        )
      end

      def refresh_access_token(refresh_token)
        post_token(grant_type: "refresh_token", refresh_token: refresh_token)
      end

      private

      def post_token(params)
        uri = URI.join(ACCOUNTS_HOST, "/api/token")

        request = Net::HTTP::Post.new(uri)
        request.basic_auth(Spotify.client_id, Spotify.client_secret)
        request.set_form_data(params)

        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                                                       open_timeout: 5, read_timeout: 10) do |http|
          http.request(request)
        end

        body = JSON.parse(response.body.presence || "{}")
        return body if response.code.to_i == 200

        message = body["error_description"].presence || body["error"].presence || "token request failed"
        raise AuthError.new("Spotify: #{message}", status: response.code.to_i, body: response.body)
      end
    end
  end
end
