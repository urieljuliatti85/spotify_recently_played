ENV["RAILS_ENV"] ||= "test"

# The owner-only routes require this; setting it here also lets the suite
# exercise the guard instead of tripping over it.
ENV["ADMIN_PASSWORD"] ||= "test-owner-password"

require_relative "../config/environment"
require "rails/test_help"

module TestOverrides
  # Minitest 6 dropped Object#stub, and this app only ever needs to swap a
  # single module method, so here is the smallest thing that does that.
  def stubbing(object, name, value)
    singleton = object.singleton_class
    original = singleton.instance_method(name) if singleton.instance_methods(false).include?(name)

    singleton.define_method(name) { |*| value }
    yield
  ensure
    singleton.remove_method(name)
    singleton.define_method(name, original) if original
  end

  # Swaps environment variables for the duration of the block.
  def with_env(values)
    previous = values.keys.index_with { |key| ENV[key] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end

module ActiveSupport
  class TestCase
    include TestOverrides

    parallelize(workers: :number_of_processors)
  end
end

class ActionDispatch::IntegrationTest
  def admin_headers
    credentials = ActionController::HttpAuthentication::Basic.encode_credentials("owner", ENV["ADMIN_PASSWORD"])
    { "HTTP_AUTHORIZATION" => credentials }
  end
end
