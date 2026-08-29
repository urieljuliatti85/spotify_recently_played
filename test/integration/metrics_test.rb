require "test_helper"

class MetricsTest < ActionDispatch::IntegrationTest
  test "answers 401 without credentials, same as /api-docs" do
    get "/metrics"

    assert_response :unauthorized
  end

  test "rejects the wrong password" do
    bad = ActionController::HttpAuthentication::Basic.encode_credentials("owner", "wrong")
    get "/metrics", headers: { "HTTP_AUTHORIZATION" => bad }

    assert_response :unauthorized
  end

  test "answers with Prometheus's exposition format for the owner" do
    # yabeda-rails only installs its own request counters under a real
    # `rails server`/Puma boot (it checks Rails.const_defined?(:Server)) —
    # neither is true under `bin/rails test`, so that metric is legitimately
    # absent here even though it is present in development/production (see
    # README). A metric declared directly, right here, proves the actual
    # thing this test owns: Yabeda → the Prometheus adapter → this
    # owner-gated route renders whatever is in the registry.
    Yabeda.configure do
      group :metrics_test
      counter :probe_total, comment: "Proves the exporter renders a real registered metric.", tags: []
    end
    Yabeda.metrics_test.probe_total.increment({})

    get "/metrics", headers: admin_headers

    assert_response :success
    assert_match %r{text/plain}, response.media_type
    assert_match(/metrics_test_probe_total 1(\.0)?/, response.body)
  end
end
