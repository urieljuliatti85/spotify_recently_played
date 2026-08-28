require "test_helper"

class SyncRecentlyPlayedJobTest < ActiveJob::TestCase
  test "syncs the given account rather than always the owner" do
    owner = SpotifyAccount.create!(owner: true, refresh_token: "r", access_token: "a",
                                   token_expires_at: 1.hour.from_now)
    friend = SpotifyAccount.create!(display_name: "Ana", spotify_user_id: "ana", refresh_token: "r2",
                                    access_token: "a2", token_expires_at: 1.hour.from_now)
    calls = []

    stubbing_with(Spotify::RecentlyPlayedSync, :call, ->(account, **) {
      calls << account.id
      Spotify::RecentlyPlayedSync::Result.new(imported: 0, latest_played_at: nil)
    }) do
      SyncRecentlyPlayedJob.perform_now(friend)
    end

    assert_equal [ friend.id ], calls
    assert_not_includes calls, owner.id
  end

  test "falls back to the owner when no account is given, matching the scheduler's call" do
    owner = SpotifyAccount.create!(owner: true, refresh_token: "r", access_token: "a",
                                   token_expires_at: 1.hour.from_now)
    calls = []

    stubbing_with(Spotify::RecentlyPlayedSync, :call, ->(account, **) {
      calls << account.id
      Spotify::RecentlyPlayedSync::Result.new(imported: 0, latest_played_at: nil)
    }) do
      SyncRecentlyPlayedJob.perform_now
    end

    assert_equal [ owner.id ], calls
  end

  # A missed poll just means the next one picks the plays up — this must
  # discard quietly, not retry and pile up against a listener with no token.
  test "discards without raising when nothing is linked yet" do
    assert_nothing_raised { SyncRecentlyPlayedJob.perform_now }
  end

  test "retries rather than giving up when Spotify rate-limits the sync" do
    account = SpotifyAccount.create!(owner: true, refresh_token: "r", access_token: "a",
                                     token_expires_at: 1.hour.from_now)

    stubbing_with(Spotify::RecentlyPlayedSync, :call, ->(*) { raise Spotify::RateLimitedError, "slow down" }) do
      assert_enqueued_with(job: SyncRecentlyPlayedJob) do
        SyncRecentlyPlayedJob.perform_now(account)
      end
    end
  end
end
