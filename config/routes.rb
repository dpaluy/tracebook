Tracebook::Engine.routes.draw do
  root to: redirect("actors")

  # Actor hierarchy: /actors/vendor_users/123/sessions/abc123
  get "actors", to: "actors#index", as: :actors
  get "actors/:type/:id", to: "actors#show", as: :actor
  get "actors/:type/:id/sessions/:session_id", to: "actors#llm_session", as: :actor_session

  resources :interactions, only: [ :index, :show ] do
    post :review, on: :member
    post :bulk_review, on: :collection
    resources :comments, only: [ :create ]
  end

  resources :exports, only: [ :create, :show ]
end
