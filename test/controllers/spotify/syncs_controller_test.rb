require "test_helper"

module Spotify
  class SyncsControllerTest < ActionDispatch::IntegrationTest
    test "a cross-site post is refused" do
      post spotify_sync_path, headers: { "HTTP_SEC_FETCH_SITE" => "cross-site" }

      assert_response :forbidden
    end

    test "a same-site post is refused too" do
      post spotify_sync_path, headers: { "HTTP_SEC_FETCH_SITE" => "same-site" }

      assert_response :forbidden
    end

    # curl and cron send no Sec-Fetch-* headers at all; the site's own fetch()
    # sends same-origin. Both are the real callers, need no credential of
    # their own any more, and have to get through.
    test "a request without Sec-Fetch headers reaches the sync" do
      post spotify_sync_path

      assert_response :precondition_required
      assert_match "No Spotify account linked", response.parsed_body["error"]
    end

    test "a same-origin post reaches the sync" do
      post spotify_sync_path, headers: { "HTTP_SEC_FETCH_SITE" => "same-origin" }

      assert_response :precondition_required
    end
  end
end
