require "test_helper"

module DiscogsShelf
  class ClientTest < ActiveSupport::TestCase
    FakeResponse = Struct.new(:code, :body)

    def client_with(response)
      Client.new("http://discogs-shelf.test").tap do |client|
        client.define_singleton_method(:perform) { |*| response }
      end
    end

    test "a 200 with an invalid JSON body raises Error instead of a bare JSON::ParserError" do
      client = client_with(FakeResponse.new("200", "<html>not json</html>"))

      error = assert_raises(Error) { client.profile }
      assert_match(/invalid response/, error.message)
    end

    test "the network being unreachable raises UnreachableError, not a bare socket error" do
      client = Client.new("http://discogs-shelf.test")

      stubbing_with(Net::HTTP, :start, ->(*) { raise SocketError, "getaddrinfo failed" }) do
        assert_raises(UnreachableError) { client.profile }
      end
    end

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
