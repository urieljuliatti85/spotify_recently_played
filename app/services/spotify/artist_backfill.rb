module Spotify
  # Rows stored before the artist tables existed only know their credits as one
  # joined string, and that string cannot be split back apart reliably — a
  # comma is as likely to sit inside a name ("Tyler, The Creator") as between
  # two of them. Asking Spotify again is the only way to recover real credits.
  #
  # Also fills artist photos, which the simplified artist objects nested in a
  # track never carry.
  class ArtistBackfill
    Result = Struct.new(:linked_tracks, :imaged_artists, keyword_init: true)

    BATCH = 50

    def self.call(...) = new(...).call

    def initialize(account = SpotifyAccount.current, client: nil)
      raise NotConnectedError, "No Spotify account linked yet" if account.nil?

      @client = client || Client.new(account)
    end

    def call
      Result.new(linked_tracks: link_tracks, imaged_artists: fill_images)
    end

    # Tracks with no credits yet, re-fetched in full and relinked.
    def link_tracks(max_batches: nil)
      each_batch(Track.where.missing(:track_artists), max_batches) do |tracks|
        payloads = client.tracks(tracks.map(&:spotify_id)).index_by { |p| p["id"] }

        tracks.count do |track|
          payload = payloads[track.spotify_id]
          payload && track.sync_artists!(payload["artists"]).any?
        end
      end
    end

    # Artists still missing a photo. Once every artist has one this issues no
    # requests at all, which is what makes it safe to call on every sync.
    def fill_images(max_batches: nil)
      each_batch(Artist.where(image_url: nil), max_batches) do |artists|
        payloads = client.artists(artists.map(&:spotify_id)).index_by { |p| p["id"] }

        artists.count do |artist|
          image = Track.pick_image(payloads.dig(artist.spotify_id, "images"))
          image.present? && artist.update!(image_url: image)
        end
      end
    end

    private

    attr_reader :client

    # Paging is by primary key, so rows dropping out of `scope` as they are
    # filled in cannot make the cursor skip anything it has not seen.
    def each_batch(scope, max_batches)
      done = 0
      batches = 0

      scope.find_in_batches(batch_size: BATCH) do |batch|
        done += yield(batch)
        batches += 1
        break if max_batches && batches >= max_batches
      end

      done
    end
  end
end
