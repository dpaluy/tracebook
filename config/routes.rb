Tracebook::Engine.routes.draw do
  root to: redirect("chats")

  resources :chats, only: [ :index, :show ] do
    member do
      post :review
    end
    resources :comments, only: [ :create ]
  end
end
