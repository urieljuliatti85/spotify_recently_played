module Lrclib
  class Error < StandardError; end

  # Raised only internally to tell "no exact match" (expected, worth falling
  # back from) apart from a real failure.
  class NotFound < Error; end
end
