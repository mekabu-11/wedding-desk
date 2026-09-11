Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  resource :session, only: %i[new create destroy]
  get "help", to: "help#show", as: :help
  get "help/usage.css", to: "help#stylesheet", as: :help_stylesheet
  get "help/screenshots/:name", to: "help#screenshot", as: :help_screenshot
  resource :wedding, only: %i[new create edit update]
  get "wedding/cover-photo", to: "wedding_cover_photos#show", as: :wedding_cover_photo
  resource :membership, only: :create
  resources :documents, only: %i[index new create show destroy] do
    post :retry_analysis, on: :member
    post :organize, on: :member
    post :sample, on: :collection
    resources :attachments, only: :show, controller: "document_attachments"
    resources :candidates, only: :update
  end
  resources :change_sets, only: :show do
    post :apply, on: :member
  end
  resources :tasks, only: %i[index new create edit update] do
    post :bulk_preview, on: :collection
    post :bulk_update, on: :collection
  end
  get "wedding/export", to: "exports#show", as: :wedding_export
  resources :task_imports, only: %i[new create show update]
  resources :spreadsheet_imports, only: %i[new create show update]
  resources :guests, only: %i[index new create edit update destroy]
  resources :households, only: %i[new create edit update destroy]
  resources :seating_tables, only: %i[new create edit update destroy]
  resources :cash_gift_rules, only: %i[new create edit update destroy]
  resources :gift_sets, only: %i[new create edit update destroy]
  resources :gift_assignments, only: %i[new create edit update destroy]
  resources :guest_gift_assignments, only: %i[new create edit update destroy]
  resources :budget_items, only: %i[index new create edit update destroy] do
    resources :money_movements, only: %i[new create edit update destroy]
  end
  resources :planning_items do
    resources :planning_options, only: %i[create]
  end
  resources :planning_options, only: %i[edit update destroy] do
    post :select, on: :member
    post :reject, on: :member
    post :restore, on: :member
    resource :music_detail, only: %i[create update]
  end
  resources :planning_cost_links, only: %i[create destroy]
  resources :task_planning_links, only: %i[create destroy]
  root "dashboard#show"
end
