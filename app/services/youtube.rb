module Youtube
  class Error < StandardError; end

  class << self
    def api_key
      ENV["YOUTUBE_API_KEY"].presence || Rails.application.credentials.dig(:youtube, :api_key).presence
    end

    def configured?
      api_key.present?
    end
  end
end
