class Play < ApplicationRecord
  belongs_to :track
  belongs_to :spotify_account

  # An instant identifies a play within one listener's history, not across all
  # of them: two people playing something at the same second is ordinary.
  validates :played_at, presence: true, uniqueness: { scope: :spotify_account_id }

  scope :recent, -> { order(played_at: :desc) }
  scope :before, ->(time) { time.present? ? where(played_at: ...time) : all }
  # A subquery rather than a join, so this composes with `includes` without the
  # two of them fighting over the same table alias.
  scope :on_the_feed, -> { where(spotify_account_id: SpotifyAccount.where(visible: true).select(:id)) }
  scope :by_listener, ->(id) { id.present? ? where(spotify_account_id: id) : all }
end
