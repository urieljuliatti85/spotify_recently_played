# Single-row table holding the OAuth tokens for the one account this site mirrors.
class SpotifyAccount < ApplicationRecord
  encrypts :access_token
  encrypts :refresh_token

  # Refresh a little early so a token never expires mid-request.
  EXPIRY_MARGIN = 60.seconds

  def self.current
    first
  end

  def self.connected?
    current&.refresh_token.present?
  end

  def token_expired?
    token_expires_at.nil? || token_expires_at <= EXPIRY_MARGIN.from_now
  end

  # Always returns a usable access token, refreshing it when needed.
  def fresh_access_token
    refresh! if token_expired?
    access_token
  end

  def refresh!
    payload = Spotify::Authorization.refresh_access_token(refresh_token)

    update!(
      access_token: payload["access_token"],
      # Spotify only re-issues a refresh token occasionally; keep the old one otherwise.
      refresh_token: payload["refresh_token"].presence || refresh_token,
      token_expires_at: payload["expires_in"].to_i.seconds.from_now,
      scope: payload["scope"].presence || scope
    )
  end
end
