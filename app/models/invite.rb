# A single-use, expiring link that lets one friend link their own Spotify
# account without ever seeing ADMIN_PASSWORD.
class Invite < ApplicationRecord
  belongs_to :spotify_account, optional: true

  LIFETIME = 7.days

  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true
  # Required, unlike the free-text label this replaced: the whole point is
  # that the link only works for the Spotify account it names, so there is
  # nothing meaningful to issue an invite for without it.
  validates :spotify_user_id, presence: true

  scope :claimable, -> { where(claimed_at: nil).where(expires_at: Time.current..) }

  # Only ever set on the instance that just issued the token: the raw value is
  # shown once and never stored, so a leaked database gives up nothing usable.
  attr_reader :token

  AlreadyClaimedError = Class.new(StandardError)
  # Raised at the callback when the Spotify account that just authorized is
  # not the one this invite names — see Spotify::SessionsController#link_account.
  WrongAccountError = Class.new(StandardError)

  def self.issue!(spotify_user_id:, lifetime: LIFETIME)
    token = SecureRandom.urlsafe_base64(32)
    invite = create!(
      token_digest: digest(token),
      spotify_user_id: spotify_user_id.to_s.strip,
      expires_at: lifetime.from_now
    )
    invite.instance_variable_set(:@token, token)
    invite
  end

  # Looked up by digest, so the stored value is useless as a credential and the
  # comparison never touches the raw token.
  def self.claimable_by(token)
    return nil if token.blank?

    claimable.find_by(token_digest: digest(token))
  end

  def self.digest(token)
    OpenSSL::Digest::SHA256.hexdigest(token)
  end

  # The controller already checks `claimable_by` before starting the OAuth
  # round trip, but that check-then-act gap is real: two callbacks racing for
  # the same invite could both pass it and then both call `claim!`. The
  # `where(claimed_at: nil)` here — not a plain `update!` — is what makes only
  # one of them actually win; the other gets back 0 updated rows.
  def claim!(account)
    updated = self.class.where(id: id, claimed_at: nil)
                        .update_all(claimed_at: Time.current, spotify_account_id: account.id)
    raise AlreadyClaimedError, "This invite has already been claimed" if updated.zero?

    reload
  end

  def claimed? = claimed_at.present?
  def expired? = expires_at <= Time.current
end
