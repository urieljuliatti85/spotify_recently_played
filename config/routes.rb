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

  # Owner-only account linking.
  scope :spotify, module: :spotify, as: :spotify do
    get    "connect",  to: "sessions#new",     as: :connect
    get    "callback", to: "sessions#create",  as: :callback
    delete "",         to: "sessions#destroy", as: :session
    post   "sync",     to: "syncs#create",     as: :sync
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
