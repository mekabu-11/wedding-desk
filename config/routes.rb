Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  resource :session, only: %i[new create destroy]
  get "help", to: "help#show", as: :help
  get "help/screenshots/:name", to: "help#screenshot", as: :help_screenshot
  resource :wedding, only: %i[new create edit update]
  resources :documents, only: %i[index new create show destroy] do
    post :retry_analysis, on: :member
    post :sample, on: :collection
    resources :candidates, only: :update
  end
  resources :tasks, only: %i[index new create edit update]
  resources :task_imports, only: %i[new create show update]
  root "dashboard#show"
end
