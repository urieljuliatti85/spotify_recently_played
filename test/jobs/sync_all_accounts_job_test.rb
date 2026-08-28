require "test_helper"

class SyncAllAccountsJobTest < ActiveJob::TestCase
  test "enqueues one sync job per connected listener, not one job for everyone" do
    linked = SpotifyAccount.create!(owner: true, refresh_token: "r", access_token: "a",
                                    token_expires_at: 1.hour.from_now)
    another = SpotifyAccount.create!(display_name: "Ana", spotify_user_id: "ana", refresh_token: "r2",
                                     access_token: "a2", token_expires_at: 1.hour.from_now)
    SpotifyAccount.create!(display_name: "No token", spotify_user_id: "no-token")

    assert_enqueued_jobs 2, only: SyncRecentlyPlayedJob do
      SyncAllAccountsJob.perform_now
    end

    assert_enqueued_with(job: SyncRecentlyPlayedJob, args: [ linked ])
    assert_enqueued_with(job: SyncRecentlyPlayedJob, args: [ another ])
  end

  test "enqueues nothing when no account has ever been linked" do
    assert_enqueued_jobs 0 do
      SyncAllAccountsJob.perform_now
    end
  end
end
