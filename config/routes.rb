# frozen_string_literal: true

Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      resources :hazard_points, only: %i[index create] do
        resources :evidence_snapshots, only: %i[create]
      end
      resources :strategy_versions, only: %i[index create] do
        member do
          post :publish
          post :retire
        end
      end
      resources :priorities, only: %i[create] do
        member { get :explanation }
      end
      resources :queue_snapshots, only: %i[index show create]
      get "inspection_queue" => "inspection_queue#index"
    end
  end
end
