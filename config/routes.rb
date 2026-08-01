Rails.application.routes.draw do
  # Health check for load balancers / uptime monitors.
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      resources :hazard_points, only: %i[index show create] do
        resources :evidence_snapshots, only: %i[index create]
      end

      resources :evidence_snapshots, only: %i[show] do
        # Compute a priority score for this immutable snapshot.
        post :priority, to: "priorities#compute"
      end

      resources :scoring_policies, only: %i[index show create] do
        member do
          post :publish
          patch :bound
        end
        # Stable, keyset-paginated queue for a policy version.
        get :queue, to: "priorities#queue"
        # Build a named, frozen queue-read snapshot pinned to this policy.
        resources :queue_snapshots, only: %i[create]
      end

      resources :queue_snapshots, only: %i[show] do
        member do
          get :page
        end
      end

      resources :priority_scores, only: [] do
        member do
          get :explanation, to: "priorities#explain"
        end
      end
    end
  end
end
