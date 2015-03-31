class WordpressUsersController < ApplicationController

  include HoboPermissionsHelper

  def show
    @wordpress_user = WordpressUser.with_all_fields.find(params[:id])
  end

  def index
    params[:search] ||= ""
    @wordpress_users = WordpressUser.with_all_fields.fuzzy_search(params[:search]).paginate(:page => params[:page])
  end

end
