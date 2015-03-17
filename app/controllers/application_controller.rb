class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :exception

  include Hobo::Controller::AuthenticationSupport
  before_filter :authenticate, :except => [:login, :forgot_password, :reset_password, :do_reset_password]

  def authenticate
    if logged_in?
      true
    else
      redirect_to '/login'
    end
  end
end
