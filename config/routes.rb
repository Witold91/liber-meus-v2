Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  scope "(:locale)", locale: /en|pl/ do
    resource :scenario_select, controller: :scenario_select, only: [ :show, :create ]

    resources :games, only: [ :show ] do
      post :continue, on: :member
    end

    root to: "scenario_select#show"
  end
end
