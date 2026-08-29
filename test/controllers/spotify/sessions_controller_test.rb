require "test_helper"

module Spotify
  class SessionsControllerTest < ActionDispatch::IntegrationTest
    CREDENTIALS = { "SPOTIFY_CLIENT_ID" => "cid", "SPOTIFY_CLIENT_SECRET" => "secret" }.freeze

    test "the owner routes are closed without the admin password" do
      get spotify_connect_path
      assert_response :unauthorized
    end

    test "connect is unavailable until credentials are configured" do
      with_env("SPOTIFY_CLIENT_ID" => nil, "SPOTIFY_CLIENT_SECRET" => nil) do
        get spotify_connect_path, headers: admin_headers
        assert_response :service_unavailable
      end
    end

    test "connect redirects to Spotify with the scope and a random state" do
      with_env(CREDENTIALS) do
        get spotify_connect_path, headers: admin_headers

        assert_response :redirect
        assert_match %r{\Ahttps://accounts\.spotify\.com/authorize\?}, response.location
        assert_match(/state=\h{32}/, response.location)
        assert_match(/scope=user-read-recently-played/, response.location)
        assert_match(/client_id=cid/, response.location)
      end
    end

    test "the callback rejects a mismatched state" do
      with_env(CREDENTIALS) do
        get spotify_connect_path, headers: admin_headers
        get spotify_callback_path, params: { code: "x", state: "forged" }, headers: admin_headers

        assert_response :bad_request
        assert_match "Invalid OAuth state", response.body
      end
    end

    test "the callback rejects a request that never started here" do
      get spotify_callback_path, params: { code: "x", state: "whatever" }, headers: admin_headers

      assert_response :bad_request
    end

    test "the callback reports a denied authorization without echoing the reason" do
      get spotify_callback_path, params: { error: "access_denied" }, headers: admin_headers

      assert_response :bad_request
      assert_match "Spotify denied the request", response.body
      assert_no_match(/access_denied/, response.body)
    end

    # --- friends joining by invite -------------------------------------------

    def fake_spotify(id:, name:, tokens: nil)
      profile = Object.new
      profile.define_singleton_method(:me) do
        { "id" => id, "display_name" => name, "images" => [ { "url" => "face.jpg", "width" => 300 } ] }
      end
      exchanged = tokens || { "access_token" => "at", "refresh_token" => "rt",
                              "expires_in" => 3600, "scope" => "user-read-recently-played" }

      stubbing(Authorization, :exchange_code, exchanged) do
        stubbing(Client, :with_token, profile) { yield }
      end
    end

    test "joining without confirming shows the warning page instead of redirecting" do
      invite = Invite.issue!(spotify_user_id: "ana")

      with_env(CREDENTIALS) do
        get spotify_join_path(token: invite.token)

        assert_response :success
        assert_match "ana", response.body
        assert_match(/signed in to Spotify as that account/, response.body)
        assert_nil session[:spotify_oauth_state], "must not start the OAuth round trip before confirming"
      end
    end

    test "a friend joins with an invite and never sees the admin password" do
      SpotifyAccount.create!(display_name: "Owner", spotify_user_id: "owner", owner: true)
      invite = Invite.issue!(spotify_user_id: "ana")

      with_env(CREDENTIALS) do
        # No admin_headers anywhere in this flow.
        get spotify_join_path(token: invite.token, confirmed: true)
        assert_response :redirect
        assert_match(/scope=user-read-recently-played&/, response.location)
        assert_no_match(/playlist-read-private/, response.location,
                        "a friend is never asked for playlist access the site cannot use")

        state = session[:spotify_oauth_state]
        fake_spotify(id: "ana", name: "Ana") do
          get spotify_callback_path, params: { code: "c", state: state }
        end
      end

      assert_response :redirect
      account = SpotifyAccount.find_by(spotify_user_id: "ana")
      assert_equal "Ana", account.display_name
      assert_equal "face.jpg", account.avatar_url
      assert_not account.owner, "an invite must never hand over ownership"
      assert_equal account, invite.reload.spotify_account
      assert_predicate invite, :claimed?
    end

    test "an invite is refused when a different Spotify account authorizes" do
      invite = Invite.issue!(spotify_user_id: "ana")

      with_env(CREDENTIALS) do
        get spotify_join_path(token: invite.token, confirmed: true)
        state = session[:spotify_oauth_state]

        # Whoever this browser happens to be signed in to Spotify as — not
        # the account the invite was issued to.
        fake_spotify(id: "someone-else", name: "Someone Else") do
          get spotify_callback_path, params: { code: "c", state: state }
        end
      end

      assert_response :forbidden
      assert_nil SpotifyAccount.find_by(spotify_user_id: "someone-else")
      assert_not invite.reload.claimed?
    end

    test "an invite link cannot be spent twice" do
      invite = Invite.issue!(spotify_user_id: "ana")
      token = invite.token
      invite.claim!(SpotifyAccount.create!(display_name: "Ana", spotify_user_id: "ana"))

      get spotify_join_path(token: token, confirmed: true)

      assert_response :not_found
      assert_match "invalid, already used, or expired", response.body
    end

    test "an unknown invite token is refused before anyone reaches Spotify" do
      with_env(CREDENTIALS) do
        get spotify_join_path(token: "made-up")
      end

      assert_response :not_found
    end

    test "an invite claimed mid-flow cannot be claimed again at the callback" do
      invite = Invite.issue!(spotify_user_id: "ana")

      with_env(CREDENTIALS) do
        get spotify_join_path(token: invite.token, confirmed: true)
        state = session[:spotify_oauth_state]

        # Somebody else spends it while this browser is away at Spotify.
        invite.claim!(SpotifyAccount.create!(display_name: "First", spotify_user_id: "first"))

        fake_spotify(id: "ana", name: "Ana") do
          get spotify_callback_path, params: { code: "c", state: state }
        end
      end

      assert_response :gone
      assert_nil SpotifyAccount.find_by(spotify_user_id: "ana")
    end

    test "re-authorizing updates the existing row instead of adding a listener" do
      existing = SpotifyAccount.create!(display_name: "Old name", spotify_user_id: "ana", owner: true)

      with_env(CREDENTIALS) do
        get spotify_connect_path, headers: admin_headers
        state = session[:spotify_oauth_state]

        fake_spotify(id: "ana", name: "Ana") do
          get spotify_callback_path, params: { code: "c", state: state }
        end
      end

      assert_equal 1, SpotifyAccount.count
      assert_equal "Ana", existing.reload.display_name
      assert existing.owner, "re-authorizing must not demote the owner"
    end

    test "the first account to link owns the site" do
      with_env(CREDENTIALS) do
        get spotify_connect_path, headers: admin_headers
        state = session[:spotify_oauth_state]

        fake_spotify(id: "first", name: "First") do
          get spotify_callback_path, params: { code: "c", state: state }
        end
      end

      assert SpotifyAccount.find_by(spotify_user_id: "first").owner
    end

    test "the owner sign-in route challenges, then drops the browser back on the feed" do
      get spotify_owner_path
      assert_response :unauthorized

      get spotify_owner_path, params: { view: "playlists" }, headers: admin_headers
      assert_redirected_to root_path(view: "playlists")
    end
  end
end
