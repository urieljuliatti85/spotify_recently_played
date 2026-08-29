require "test_helper"

# Only wired into the stack in development (see
# config/environments/development.rb), so this exercises the class directly
# rather than through a mounted route — the test environment never adds it.
class RedirectLocalhostToLoopbackTest < ActiveSupport::TestCase
  def call(env)
    downstream = ->(_inner_env) { [ 200, {}, [ "ok" ] ] }
    RedirectLocalhostToLoopback.new(downstream).call(env)
  end

  test "redirects localhost to the loopback IP, keeping the port, path and query string" do
    env = Rack::MockRequest.env_for("http://localhost:3000/spotify/join/abc?view=metrics")

    status, headers, = call(env)

    assert_equal 302, status
    assert_equal "http://127.0.0.1:3000/spotify/join/abc?view=metrics", headers["Location"]
  end

  test "leaves 127.0.0.1 alone" do
    env = Rack::MockRequest.env_for("http://127.0.0.1:3000/")

    status, _headers, body = call(env)

    assert_equal 200, status
    assert_equal "ok", body.first
  end

  test "leaves an unrelated host alone" do
    env = Rack::MockRequest.env_for("http://example.com/")

    status, _headers, body = call(env)

    assert_equal 200, status
    assert_equal "ok", body.first
  end
end
