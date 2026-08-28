require "test_helper"

module Spotify
  # Every other test in the suite stubs Client itself out, so this is the only
  # place `#handle` — the code that turns a raw Spotify HTTP response into an
  # expired token, a rate limit, or a missing resource — actually runs.
  class ClientTest < ActiveSupport::TestCase
    FakeResponse = Struct.new(:code, :body, :headers) do
      def [](key) = headers&.fetch(key, nil)
    end

    def client_with(response)
      account = SpotifyAccount.new(access_token: "a", token_expires_at: 1.hour.from_now)
      client = Client.new(account)
      client.define_singleton_method(:perform) { |*| response }
      client
    end

    test "an expired or revoked token raises AuthError, not a bare HTTP error" do
      client = client_with(FakeResponse.new("401", "{}"))

      error = assert_raises(AuthError) { client.me }
      assert_equal 401, error.status
    end

    test "a missing resource raises NotFoundError" do
      client = client_with(FakeResponse.new("404", "{}"))

      assert_raises(NotFoundError) { client.playlist("gone") }
    end

    test "fetch_each treats a 404 for one id as absent rather than a failure" do
      client = client_with(FakeResponse.new("404", "{}"))

      assert_equal [], client.artists([ "gone" ])
    end

    test "429 raises RateLimitedError and carries Retry-After" do
      client = client_with(FakeResponse.new("429", "{}", { "Retry-After" => "17" }))

      error = assert_raises(RateLimitedError) { client.me }
      assert_equal 17, error.retry_after
    end

    test "an unrecognized failure status still raises, with the status attached" do
      client = client_with(FakeResponse.new("503", "Service Unavailable"))

      error = assert_raises(Error) { client.me }
      assert_equal 503, error.status
    end

    test "a 200 with an empty body parses as an empty payload instead of raising" do
      client = client_with(FakeResponse.new("200", ""))

      assert_equal({}, client.me)
    end

    test "204 (no content) returns nil rather than parsing a missing body" do
      client = client_with(FakeResponse.new("204", ""))

      assert_nil client.me
    end
  end
end
