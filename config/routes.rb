Tracebook::Engine.routes.draw do
  root to: redirect("interactions")

  resources :interactions, only: [ :index, :show ] do
    post :review, on: :member
    post :bulk_review, on: :collection
  end

  resources :exports, only: [ :create, :show ]
end
