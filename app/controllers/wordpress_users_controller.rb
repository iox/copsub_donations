class WordpressUsersController < ApplicationController

  include HoboPermissionsHelper

  def show
    @wordpress_user = WordpressUser.with_all_fields.find(params[:id])
  end

  def index
    params[:search] ||= ""

    scope = WordpressUser.with_all_fields.fuzzy_search(params[:search])
    scope = params[:last_year_less_than] ? scope.having("IFNULL(sum(copsub_donations.donations.amount_in_dkk),0) < #{params[:last_year_less_than].to_i}") : scope

    @wordpress_users = scope.paginate(:page => params[:page])
  end

end
