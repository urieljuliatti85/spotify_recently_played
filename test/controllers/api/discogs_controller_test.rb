require "test_helper"

module Api
  class DiscogsControllerTest < ActionDispatch::IntegrationTest
    setup do
      Rails.cache.clear
      DiscogsMatch.delete_all
    end

    def shelf(items: [], release: nil, profile: nil, raises: nil)
      fake = Object.new
      fake.define_singleton_method(:items) do |_list, _params = {}|
        raise raises if raises
        { "items" => items, "pagination" => { "page" => 1, "total_pages" => 1, "total" => items.size } }
      end
      fake.define_singleton_method(:release) do |_id|
        raise raises if raises
        release
      end
      fake.define_singleton_method(:profile) do
        raise raises if raises
        profile
      end
      fake
    end

    def a_release
      {
        "discogs_id" => 42,
        "title" => "Prey To The World",
        "artist" => "Wolfbrigade",
        "year" => 2007,
        "cover_url" => "cover.jpg",
        "genres" => [ "Rock" ],
        "images" => [ { "uri" => "huge.jpg" } ],
        "tracklist" => [
          { "position" => "", "title" => "Side A", "type" => "heading" },
          { "position" => "A1", "title" => "Pray", "type" => "track" },
          { "position" => "A2", "title" => "Mindprowler", "type" => "track" }
        ]
      }
    end

    def a_match
      {
        "album" => { "spotify_id" => "alb", "name" => "Prey To The World", "spotify_url" => "https://album" },
        "market" => "BR",
        "track_count" => 2,
        "playable_count" => 1,
        "tracks" => [
          { "position" => "A1", "title" => "Pray", "track" => nil, "source" => nil },
          { "position" => "A2", "title" => "Mindprowler", "source" => "search",
            "track" => { "spotify_id" => "t2", "name" => "Mindprowler", "playable" => true } }
        ]
      }
    end

    test "the list reports matches already worked out and nothing else" do
      DiscogsMatch.create!(discogs_id: 42, spotify_album_id: "alb", track_count: 2,
                           playable_count: 1, payload: a_match, matched_at: Time.current)

      items = [ { "discogs_id" => 42, "title" => "Prey To The World" },
                { "discogs_id" => 99, "title" => "Never opened" } ]

      stubbing(DiscogsShelf::Client, :new, shelf(items: items)) do
        get api_discogs_releases_path
      end

      assert_response :success
      matched, unknown = response.parsed_body["items"]
      assert_equal 1, matched["spotify"]["playable_count"]
      # No row means nobody has opened it, which is not the same as "missing".
      assert_nil unknown["spotify"]
    end

    test "a record carries every Discogs row, matched or not" do
      stubbing(DiscogsShelf::Client, :new, shelf(release: a_release)) do
        stubbing(Spotify::ReleaseMatcher, :call, a_match) do
          get api_discogs_release_path(42)
        end
      end

      assert_response :success
      body = response.parsed_body

      assert_equal "Wolfbrigade", body.dig("release", "artist")
      # The sleeve scans the shelf carries are not worth the bytes here.
      assert_nil body["release"]["images"]

      titles = body["tracks"].map { |track| track["title"] }
      assert_equal [ "Side A", "Pray", "Mindprowler" ], titles
      assert_equal [ false, false, true ], body["tracks"].map { |track| track["playable"] }
      assert_equal "t2", body["tracks"].last.dig("track", "spotify_id")
      assert_equal "alb", body.dig("spotify", "album", "spotify_id")
    end

    test "the match is computed once and then read from the cache" do
      calls = 0
      match = a_match

      stubbing(DiscogsShelf::Client, :new, shelf(release: a_release)) do
        stubbing_with(Spotify::ReleaseMatcher, :call, ->(_release) { calls += 1; match }) do
          get api_discogs_release_path(42)
          get api_discogs_release_path(42)
        end
      end

      assert_response :success
      assert_equal 1, calls
      assert_equal 1, DiscogsMatch.count
    end

    test "a record still opens when Spotify cannot be reached" do
      failing = ->(_release) { raise Spotify::NotConnectedError, "no account" }

      stubbing(DiscogsShelf::Client, :new, shelf(release: a_release)) do
        stubbing_with(Spotify::ReleaseMatcher, :call, failing) do
          get api_discogs_release_path(42)
        end
      end

      assert_response :success
      assert_equal 3, response.parsed_body["tracks"].size
      assert_equal [ false, false, false ], response.parsed_body["tracks"].map { |t| t["playable"] }
      assert_match "No Spotify account", response.parsed_body.dig("spotify", "error")
    end

    test "an unreachable shelf answers 503 rather than a stack trace" do
      failure = DiscogsShelf::UnreachableError.new("Discogs Shelf at http://x did not answer")

      stubbing(DiscogsShelf::Client, :new, shelf(raises: failure)) do
        get api_discogs_releases_path
      end

      assert_response :service_unavailable
      assert_match "did not answer", response.parsed_body["error"]
    end

    test "status reports an unreachable shelf without failing" do
      failure = DiscogsShelf::UnreachableError.new("nothing there")

      with_env("DISCOGS_SHELF_URL" => "http://127.0.0.1:3999") do
        stubbing(DiscogsShelf::Client, :new, shelf(raises: failure)) do
          get api_discogs_status_path
        end
      end

      assert_response :success
      assert_equal true, response.parsed_body["configured"]
      assert_equal false, response.parsed_body["reachable"]
    end
  end
end
