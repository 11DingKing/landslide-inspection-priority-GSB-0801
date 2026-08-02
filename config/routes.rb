Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      resources :hazard_points do
        member do
          post :calculate_priority, to: "priorities#calculate"
          get :priority, to: "priorities#show"
          get :priority_explanation, to: "priorities#explanation"
        end
        resources :snapshots, only: [:index], controller: "snapshots"
      end

      resources :snapshots, only: [:index, :show] do
        member do
          post :replay, to: "snapshots#replay"
        end
      end

      resources :strategies, only: [:index, :show, :create] do
        member do
          post :publish
        end
        collection do
          get :active
        end
      end

      get "queue", to: "queue#index"

      resources :queue_reads, only: [:create, :show], param: :business_id
    end
  end
end
