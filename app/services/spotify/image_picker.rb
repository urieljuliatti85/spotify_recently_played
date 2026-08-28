module Spotify
  # Spotify returns images widest-first, for tracks, artists, playlists,
  # albums and the logged-in user's own profile alike. The middle one
  # (~300px) is the best fit for a thumbnail without wasting bandwidth.
  class ImagePicker
    def self.call(images)
      images = Array(images)
      return nil if images.empty?

      (images.find { |i| i["width"].to_i.between?(200, 400) } || images.last)["url"]
    end
  end
end
