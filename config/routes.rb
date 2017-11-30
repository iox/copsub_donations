CopsubDonations::Application.routes.draw do
  get ENV['RAILS_RELATIVE_URL_ROOT'] => 'front#index' if ENV['RAILS_RELATIVE_URL_ROOT']
  root :to => 'donations#index'
  get 'users/:id/reset_password_from_email/:key' => 'users#reset_password', :as => 'reset_password_from_email'
  get 'users/:id/accept_invitation_from_email/:key' => 'users#accept_invitation', :as => 'accept_invitation_from_email'
  get 'users/:id/activate_from_email/:key' => 'users#activate', :as => 'activate_from_email'
  post 'search' => 'front#search', :as => 'site_search_post'
  get 'search' => 'front#search', :as => 'site_search'

  get '/import' => 'front#index'
  get '/import_donations_from_wordpress' => 'donations#import_donations_from_wordpress'
  post '/import_donations_from_csv' => 'donations#import_donations_from_csv'
  get '/assign_donation' => 'donations#assign_donation'
  get '/unassign_donation' => 'donations#unassign_donation'

  get '/mailchimp_email_preview' => 'donors#mailchimp_email_preview'
  post '/send_mailchimp_email' => 'donors#send_mailchimp_email'

  get '/change_roles_preview' => 'donors#change_roles_preview'
  post '/change_roles_assign' => 'donors#change_roles_assign'

  get '/find_duplicated_donors' => 'donors#find_duplicated_donors'
  get '/delete_duplicated_donor/:id' => 'donors#delete_duplicated_donor'


  post '/paypal_ipn' => 'paypal#ipn'
  get '/paypal_ipn' => 'paypal#ipn'
  post '/paypal/generate_payment_token'
  post '/paypal/execute_billing_agreement'

  post '/api/new_donor' => 'donors#new_donor'
  post '/api/new_bank_donor' => 'donors#new_bank_donor' # OLD API, TO BE DELETED

  post '/api/stripe/subscribe' => 'stripe#subscribe'
  post '/api/stripe/donate' => 'stripe#donate'

  get '/documentation' => 'front#documentation'

  get '/role_changes' => 'role_changes#index'

  # The priority is based upon order of creation: first created -> highest priority.
  # See how all your routes lay out with "rake routes".

  # You can have the root of your site routed with "root"
  # root 'welcome#index'

  # Example of regular route:
  #   get 'products/:id' => 'catalog#view'

  # Example of named route that can be invoked with purchase_url(id: product.id)
  #   get 'products/:id/purchase' => 'catalog#purchase', as: :purchase

  # Example resource route (maps HTTP verbs to controller actions automatically):
  #   resources :products

  # Example resource route with options:
  #   resources :products do
  #     member do
  #       get 'short'
  #       post 'toggle'
  #     end
  #
  #     collection do
  #       get 'sold'
  #     end
  #   end

  # Example resource route with sub-resources:
  #   resources :products do
  #     resources :comments, :sales
  #     resource :seller
  #   end

  # Example resource route with more complex sub-resources:
  #   resources :products do
  #     resources :comments
  #     resources :sales do
  #       get 'recent', on: :collection
  #     end
  #   end

  # Example resource route with concerns:
  #   concern :toggleable do
  #     post 'toggle'
  #   end
  #   resources :posts, concerns: :toggleable
  #   resources :photos, concerns: :toggleable

  # Example resource route within a namespace:
  #   namespace :admin do
  #     # Directs /admin/products/* to Admin::ProductsController
  #     # (app/controllers/admin/products_controller.rb)
  #     resources :products
  #   end
end
