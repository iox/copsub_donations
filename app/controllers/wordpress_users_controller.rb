class WordpressUsersController < ApplicationController

  include HoboPermissionsHelper

  def show
    @wordpress_user = WordpressUser.with_all_fields.find(params[:id])
  end

  def index
    params[:search] ||= ""
    params[:sort] ||= "ID"
    params[:direction] ||= "asc"

    @wordpress_users = wordpress_users_scope.order("#{params[:sort]} #{params[:direction]}").paginate(:page => params[:page])

    respond_to do |format|
      format.html
      format.text { render csv: wordpress_users_scope, only: [:ID, :user_email, :user_login, :display_name], add_methods: [:user_adress, :city, :country, :user_phone, :paymentid, :paypal_id, :role] }
    end
  end

  def edit
    @wordpress_user = WordpressUser.with_all_fields.find(params[:id])
  end

  def update
    @wordpress_user = WordpressUser.with_all_fields.find(params[:id])
    @wordpress_user.update_attributes(params[:wordpress_user])
    redirect_to @wordpress_user
  end

  def change_roles_preview
    @wordpress_users = wordpress_users_scope
  end

  def change_roles_assign
    for user in wordpress_users_scope
      user.role = params[:new_role]
    end
    flash[:info] = "The selected users have been updated to the '#{params[:new_role]}' role"
    params.delete :new_role
    redirect_to wordpress_users_path
  end

  private

  def wordpress_users_scope
    scope = WordpressUser.with_all_fields.fuzzy_search(params[:search])

    if params[:donated_last_year] && !params[:last_year_from].blank? && !params[:last_year_to].blank?
      scope = scope.where("donated_last_year_in_dkk.meta_value BETWEEN #{params[:last_year_from].to_i} AND #{params[:last_year_to].to_i}")
    end

    if !params[:role].blank?
      scope = scope.where("#{PREFIX}capabilities.meta_value LIKE ?", "%#{params[:role]}%")
    end

    return scope
  end

end
