class AdminConstraint
  def matches?(request)
    return false unless request.session[:current_admin_id].present?

    admin = Administrator.find_by(id: request.session[:current_admin_id])
    admin.present?
  end
end

Rails.application.routes.draw do
  # Static pages
  scope '/pages', as: :pages do
    get 'features', to: 'pages#features', as: :features
    get 'about', to: 'pages#about', as: :about
    get 'contact', to: 'pages#contact', as: :contact
  end

  # Linear OAuth flow (browser-based, initiated by OpenClacky skill)
  namespace :oauth do
    get  'linear/authorize', to: 'linear#authorize', as: :linear_authorize
    get  'linear/callback',  to: 'linear#callback',  as: :linear_callback
  end

  # Linear webhook receiver
  namespace :webhooks do
    post 'linear', to: 'linear#receive'
  end

  # API routes
  namespace :api do
    namespace :v1 do
      get 'health', to: 'health#index'
      resources :project_mappings, only: [:index, :create, :destroy]
    end
  end

  root 'home#index'

  # Do not write business logic at admin dashboard
  namespace :admin do
    resources :admin_oplogs, only: [:index, :show]
    resources :administrators
    get 'login', to: 'sessions#new', as: :login
    post 'login', to: 'sessions#create'
    delete 'logout', to: 'sessions#destroy', as: :logout
    resource :account, only: [:edit, :update]

    # Mount GoodJob dashboard
    mount GoodJob::Engine => 'good_job', :constraints => AdminConstraint.new

    root to: 'dashboard#index'
  end

  mount ActionCable.server => '/cable'

  # Catch-all route for all 404 errors - MUST be last
  match '*path', to: 'application#handle_routing_error', via: :all,
    constraints: lambda { |request|
      !request.path.start_with?('/rails/active_storage')
    }
end
