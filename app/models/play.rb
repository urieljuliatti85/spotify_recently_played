class Play < ApplicationRecord
  belongs_to :track

  validates :played_at, presence: true, uniqueness: true

  scope :recent, -> { order(played_at: :desc) }
  scope :before, ->(time) { time.present? ? where(played_at: ...time) : all }
end
