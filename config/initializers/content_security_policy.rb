# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.object_src  :none
    policy.base_uri    :self
    policy.form_action :self
    policy.frame_ancestors :none

    # Cover art comes straight from Spotify's payloads, which name a handful of
    # rotating CDN hosts (i.scdn.co, mosaic.scdn.co, image-cdn-*.spotifycdn.com
    # and friends). Pinning that list would break album art the day Spotify adds
    # a host, and an image is not a script — https is the useful line here.
    policy.img_src     :self, :data, :https

    # The embed player and the iframe API that drives it.
    policy.script_src  :self, "https://open.spotify.com"
    policy.frame_src   "https://open.spotify.com"

    # The page only ever talks to its own /api routes; the embed does its own
    # networking from inside the iframe, under Spotify's origin, not ours.
    policy.connect_src :self

    # React writes element styles through the CSSOM, which CSP does not police,
    # but Vite injects real <style> tags — hence unsafe-inline for styles only.
    policy.style_src   :self, :unsafe_inline

    if Rails.env.development?
      vite_origin = "http://#{ViteRuby.config.host_with_port}"
      policy.script_src(*policy.script_src, :unsafe_eval, vite_origin)
      policy.connect_src(*policy.connect_src, vite_origin, "ws://#{ViteRuby.config.host_with_port}")
    end
  end

  # A fresh nonce per response. The session-id generator Rails suggests is no
  # use here: the JSON endpoints answer requests that carry no session at all.
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
end
