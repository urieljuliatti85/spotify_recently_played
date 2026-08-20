require "test_helper"

class SpotifyAccountTest < ActiveSupport::TestCase
  test "tokens are encrypted at rest" do
    account = SpotifyAccount.create!(refresh_token: "super-secret", access_token: "also-secret",
                                     token_expires_at: 1.hour.from_now)

    stored = SpotifyAccount.connection.select_value(
      "SELECT refresh_token FROM spotify_accounts WHERE id = #{account.id}"
    )

    assert_not_equal "super-secret", stored
    assert_equal "super-secret", account.reload.refresh_token
  end

  test "a token near expiry counts as expired" do
    account = SpotifyAccount.new(token_expires_at: 30.seconds.from_now)
    assert account.token_expired?
  end

  test "a token with plenty of life left is reused" do
    account = SpotifyAccount.new(token_expires_at: 10.minutes.from_now)
    assert_not account.token_expired?
  end

  test "refresh keeps the old refresh token when Spotify does not send a new one" do
    account = SpotifyAccount.create!(refresh_token: "keep-me", access_token: "old",
                                     token_expires_at: 1.second.ago)

    stubbing(Spotify::Authorization, :refresh_access_token,
             { "access_token" => "new", "expires_in" => 3600 }) do
      account.refresh!
    end

    assert_equal "keep-me", account.refresh_token
    assert_equal "new", account.access_token
  end
end
