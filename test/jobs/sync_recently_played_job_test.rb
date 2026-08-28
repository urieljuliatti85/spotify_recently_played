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
  # `assert_nothing_raised` alone does not catch a regression here: neither
  # discard_on nor retry_on raises back to the caller of `perform_now`, so
  # only checking that nothing gets re-enqueued actually distinguishes the
  # two. It would not have caught NotConnectedError being retried instead of
  # discarded — ActiveJob resolves discard_on/retry_on in reverse declaration
  # order, so a broad `retry_on Spotify::Error` declared after a narrower
  # discard_on shadows it entirely for every subclass, silently.
  test "discards without retrying when nothing is linked yet" do
    assert_enqueued_jobs 0 do
      SyncRecentlyPlayedJob.perform_now
    end
  end

  test "discards without retrying when the account was unlinked before this ran" do
    account = SpotifyAccount.create!(owner: true, refresh_token: "r", access_token: "a",
                                     token_expires_at: 1.hour.from_now)

    stubbing_with(Spotify::RecentlyPlayedSync, :call, ->(*) { raise Spotify::NotConnectedError, "gone" }) do
      assert_enqueued_jobs 0 do
        SyncRecentlyPlayedJob.perform_now(account)
      end
    end
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
