class WordpressUsersController < ApplicationController

  include HoboPermissionsHelper

  def show
    @wordpress_user = WordpressUser.find(params[:id])
  end

end
