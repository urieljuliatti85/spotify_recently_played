require "test_helper"

module DiscogsShelf
  class ClientTest < ActiveSupport::TestCase
    test "adds marketplace data to every album release" do
      client = Client.new("http://discogs-shelf.test")
      items = [
        { "discogs_id" => 42, "title" => "Album", "artist" => "Artist" },
        { "discogs_id" => 99, "title" => "Album", "artist" => "Artist" }
      ]
      calls = []

      stubbing(client, :items, { "items" => items }) do
        stubbing_with(client, :marketplace, ->(id) { calls << id; { "album" => { "url" => "https://marketplace/#{id}" } } }) do
          releases = client.album_releases("Album", "Artist")

          assert_equal [ 42, 99 ], calls
          assert_equal "https://marketplace/42", releases.first.dig("marketplace", "album", "url")
          assert_equal "https://marketplace/99", releases.last.dig("marketplace", "album", "url")
        end
      end
    end
  end
end
