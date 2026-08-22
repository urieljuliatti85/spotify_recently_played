Rails.application.routes.draw do
  root "pages#index"

  namespace :api do
    resources :plays, only: :index
    get "artists/:id/tracks", to: "artists#tracks", as: :artist_tracks
    resources :playlists, only: :index do
      get :tracks, on: :member
    end
    resource :status, only: :show, controller: "status"
  end

  # Account linking: the owner's own, and a friend's via an invite.
  scope :spotify, module: :spotify, as: :spotify do
    get    "connect",       to: "sessions#new",     as: :connect
    get    "join/:token",   to: "sessions#join",    as: :join
    get    "callback",      to: "sessions#create",  as: :callback
    delete "",              to: "sessions#destroy", as: :session
    delete "listeners/:id", to: "sessions#destroy", as: :listener
    post   "sync",          to: "syncs#create",     as: :sync

    # Owner-only: the links friends use to add themselves.
    get    "invites",     to: "invites#index",   as: :invites
    post   "invites",     to: "invites#create"
    delete "invites/:id", to: "invites#destroy", as: :invite
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
