Rails.application.routes.draw do
  root "pages#index"

  namespace :api do
    resources :plays, only: :index
    get "artists/:id/tracks", to: "artists#tracks", as: :artist_tracks
    get "albums/:id/tracks", to: "albums#tracks", as: :album_tracks
    get "albums/:id/discogs", to: "albums#discogs", as: :album_discogs
    get "albums/releases", to: "albums#releases", as: :album_releases
    resources :playlists, only: :index do
      get :tracks, on: :member
    end
    resource :status, only: :show, controller: "status"

    # The Discogs shelf: browsing comes from the sibling discogs_shelf app,
    # playability from Spotify.
    get "discogs/status",       to: "discogs#status", as: :discogs_status
    get "discogs/releases",     to: "discogs#index",  as: :discogs_releases
    get "discogs/releases/:id", to: "discogs#show",   as: :discogs_release
  end

  # Account linking: the owner's own, and a friend's via an invite.
  scope :spotify, module: :spotify, as: :spotify do
    get    "connect",       to: "sessions#new",     as: :connect
    get    "join/:token",   to: "sessions#join",    as: :join
    get    "callback",      to: "sessions#create",  as: :callback
    delete "",              to: "sessions#destroy", as: :session
    delete "listeners/:id", to: "sessions#destroy", as: :listener
    post   "sync",          to: "syncs#create",     as: :sync

    # The only route that exists to be challenged. Nothing on the public feed
    # ever asks for ADMIN_PASSWORD, so without somewhere to hand it over the
    # owner-only actions can never appear in the browser: the guard answers
    # 401, the frontend never sees `admin`, and the button stays hidden.
    get "owner", to: "sessions#owner", as: :owner

    # Owner-only: build a public playlist out of what the feed has not played.
    get  "playlists/search", to: "playlists#search", as: :search_playlist_tracks
    get  "playlists/unheard", to: "playlists#unheard", as: :unheard_playlist_tracks
    post "playlists",         to: "playlists#create",  as: :playlists

    # Owner-only: the links friends use to add themselves.
    get    "invites",     to: "invites#index",   as: :invites
    post   "invites",     to: "invites#create"
    delete "invites/:id", to: "invites#destroy", as: :invite
  end

  # Where Spotify returns a *visitor* who signed in for volume control. It
  # serves the same React app; the code exchange happens in their browser, and
  # nothing about it reaches the server. Separate from /spotify/callback, which
  # links the accounts this site mirrors.
  get "listen/callback", to: "pages#index", as: :listen_callback

  get "up" => "rails/health#show", as: :rails_health_check
end
