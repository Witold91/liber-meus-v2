Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # Auth — outside locale scope so the Google callback URL is fixed
  get    "/sign_in"                     => "sessions#new",     as: :sign_in
  get    "/auth/google_oauth2/callback" => "sessions#create"
  delete "/session"                     => "sessions#destroy", as: :sign_out

  scope "(:locale)", locale: /en|pl/ do
    resource :scenario_select, controller: :scenario_select, only: [ :show, :create ]

    resources :games, only: [ :index, :show ] do
      member do
        post :continue
        post :replay_act
        post :save_game
        post :load_save
        get  :saves
      end
    end

    root to: "games#index"
  end
end
