require "test_helper"

module Lrclib
  class LyricsMatcherTest < ActiveSupport::TestCase
    def track(overrides = {})
      Track.new({
        spotify_id: "trk1", name: "Song", artist_names: "First, Second",
        album_name: "Album", duration_ms: 180_000
      }.merge(overrides))
    end

    def stub_client(get: nil, search: [])
      Object.new.tap do |client|
        client.define_singleton_method(:get) { |**| get }
        client.define_singleton_method(:search) { |**| search }
      end
    end

    test "an exact match is used without falling back to search" do
      client = stub_client(get: { "plainLyrics" => "exact" })
      client.define_singleton_method(:search) { |**| flunk "should not fall back once an exact match is found" }

      result = LyricsMatcher.call(track, client: client)

      assert_equal "exact", result["plainLyrics"]
    end

    test "falls back to search when there is no exact match" do
      client = stub_client(get: nil, search: [ { "plainLyrics" => "from search" } ])

      result = LyricsMatcher.call(track, client: client)

      assert_equal "from search", result["plainLyrics"]
    end

    test "search picks the first result with actual lyrics over an empty one" do
      client = stub_client(get: nil, search: [
        { "plainLyrics" => nil, "instrumental" => false },
        { "plainLyrics" => "here", "instrumental" => false }
      ])

      result = LyricsMatcher.call(track, client: client)

      assert_equal "here", result["plainLyrics"]
    end

    test "search accepts an instrumental result even with no text" do
      client = stub_client(get: nil, search: [ { "plainLyrics" => nil, "instrumental" => true } ])

      result = LyricsMatcher.call(track, client: client)

      assert result["instrumental"]
    end

    test "returns nil when nothing at all matches" do
      client = stub_client(get: nil, search: [])

      assert_nil LyricsMatcher.call(track, client: client)
    end

    test "only the first credited artist is sent, not the full credit line" do
      sent_artist = nil
      client = Object.new
      client.define_singleton_method(:get) do |artist_name:, **|
        sent_artist = artist_name
        nil
      end
      client.define_singleton_method(:search) { |**| [] }

      LyricsMatcher.call(track, client: client)

      assert_equal "First", sent_artist
    end

    test "a client error is swallowed, not raised" do
      client = Object.new
      client.define_singleton_method(:get) { |**| raise Error, "lrclib is down" }

      assert_nil LyricsMatcher.call(track, client: client)
    end
  end
end
