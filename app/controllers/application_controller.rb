class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :exception

  include Hobo::Controller::AuthenticationSupport
  unless Rails.env.test?
    before_filter :authenticate, :except => [:login, :forgot_password, :reset_password, :do_reset_password]
  end

  def authenticate
    if logged_in?
      true
    else
      redirect_to '/login'
    end
  end


  def override_cors_limitations
    headers['Access-Control-Allow-Origin'] = '*'
    headers['Access-Control-Allow-Methods'] = 'POST, PUT, DELETE, GET, OPTIONS'
    headers['Access-Control-Request-Method'] = '*'
  end
end
