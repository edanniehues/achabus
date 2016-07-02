Rails.application.routes.draw do
  resources :timetables
  get 'router/admin'

  get 'router/frontend'

  get 'route_tracer/trace'

  resources :route_points do
    member do
      get 'to'
    end
    collection do
      get 'closest_to'
    end
  end
  resources :points do
    member do
      post 'forward'
      post 'backward'
      post 'left'
      post 'right'
    end
  end
  get 'trace_route', to: 'route_tracer#trace'

  resources :routes
  resources :lines
  resources :line_groups

  get 'admin', to: 'router#admin'
  root to: 'router#frontend'

  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html

  # Serve websocket cable requests in-process
  # mount ActionCable.server => '/cable'
end
