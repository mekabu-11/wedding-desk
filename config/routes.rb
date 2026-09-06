Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  resource :session, only: %i[new create destroy]
  resource :wedding, only: %i[new create edit update]
  resources :documents, only: %i[index new create show destroy] do
    post :retry_analysis, on: :member
    post :sample, on: :collection
    resources :candidates, only: :update
  end
  resources :tasks, only: %i[index edit update]
  root "dashboard#show"
end
