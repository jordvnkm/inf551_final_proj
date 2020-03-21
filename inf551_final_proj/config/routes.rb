Rails.application.routes.draw do
  root 'databases#show'
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
  resource :databases,  only: [:show, :update,  :create, :destroy]
  resource :query,  only: [:show, :update,  :create, :destroy]
end
