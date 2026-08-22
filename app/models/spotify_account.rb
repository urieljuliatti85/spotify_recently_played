# One row per listener whose history this site mirrors: the owner, plus any
# friend who has claimed an invite and authorized their own account.
class SpotifyAccount < ApplicationRecord
  encrypts :access_token
  encrypts :refresh_token

  # Unlinking has to take the history with it — a friend who walks away is
  # asking for their listening to come off the page, not just to stop growing.
  has_many :plays, dependent: :destroy
  has_many :invites, dependent: :nullify

  # Refresh a little early so a token never expires mid-request.
  EXPIRY_MARGIN = 60.seconds

  validates :spotify_user_id, uniqueness: true, allow_nil: true

  scope :connected, -> { where.not(refresh_token: nil) }
  # The owner first, then everyone else by name, so the feed's listener list
  # has a stable order that does not shuffle as friends come and go.
  scope :listed, -> { where(visible: true).order(owner: :desc, display_name: :asc, id: :asc) }

  # The site belongs to one person; `owner` is the row that linked first and the
  # one the owner-only routes act on.
  def self.owner
    find_by(owner: true) || order(:id).first
  end

  def self.any_connected?
    connected.exists?
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
