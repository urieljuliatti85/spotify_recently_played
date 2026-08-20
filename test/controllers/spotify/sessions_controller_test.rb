require "test_helper"

module Spotify
  class SessionsControllerTest < ActionDispatch::IntegrationTest
    CREDENTIALS = { "SPOTIFY_CLIENT_ID" => "cid", "SPOTIFY_CLIENT_SECRET" => "secret" }.freeze

    test "the owner routes are closed without the admin password" do
      get spotify_connect_path
      assert_response :unauthorized
    end

    test "connect is unavailable until credentials are configured" do
      with_env("SPOTIFY_CLIENT_ID" => nil, "SPOTIFY_CLIENT_SECRET" => nil) do
        get spotify_connect_path, headers: admin_headers
        assert_response :service_unavailable
      end
    end

    test "connect redirects to Spotify with the scope and a random state" do
      with_env(CREDENTIALS) do
        get spotify_connect_path, headers: admin_headers

        assert_response :redirect
        assert_match %r{\Ahttps://accounts\.spotify\.com/authorize\?}, response.location
        assert_match(/state=\h{32}/, response.location)
        assert_match(/scope=user-read-recently-played/, response.location)
        assert_match(/client_id=cid/, response.location)
      end
    end

    test "the callback rejects a mismatched state" do
      with_env(CREDENTIALS) do
        get spotify_connect_path, headers: admin_headers
        get spotify_callback_path, params: { code: "x", state: "forged" }, headers: admin_headers

        assert_response :bad_request
        assert_match "Invalid OAuth state", response.body
      end
    end

    test "the callback rejects a request that never started here" do
      get spotify_callback_path, params: { code: "x", state: "whatever" }, headers: admin_headers

      assert_response :bad_request
    end

    test "the callback reports a denied authorization" do
      get spotify_callback_path, params: { error: "access_denied" }, headers: admin_headers

      assert_response :bad_request
      assert_match "access_denied", response.body
    end
  end
end
