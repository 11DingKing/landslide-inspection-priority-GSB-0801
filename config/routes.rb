Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  resources :hazard_points, only: %i[index show create update] do
    resources :evidence_snapshots, only: %i[index show create] do
      member do
        post :lock
        post :priority, to: "priorities#calculate"
      end
    end
  end

  resources :strategies, only: %i[index show create] do
    member do
      post :publish
      post :retire
    end
  end

  get  "priority/queue",          to: "priorities#queue"
  post "priority/replay",         to: "priorities#replay"
  post "priority/compute_latest", to: "priorities#compute_latest"
  get  "priority/:id/explain",    to: "priorities#explain", as: :priority_explain
end
