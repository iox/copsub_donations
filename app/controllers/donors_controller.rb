class DonorsController < ApplicationController

  hobo_model_controller

  auto_actions :all

  def index
    params[:search] ||= ""
    params[:sort] ||= "id"
    params[:direction] ||= "asc"

    @donors = donors_scope.order("#{params[:sort]} #{params[:direction]}").paginate(:page => params[:page])

    respond_to do |format|
      format.html
      format.text { render csv: donors_scope, only: [:ID, :user_email, :user_login, :display_name], add_methods: [:user_adress, :city, :country, :user_phone, :paymentid, :paypal_id, :role] }
    end
  end

  def change_roles_preview
    @donors = donors_scope
  end

  def change_roles_assign
    for user in donors_scope
      user.role = params[:new_role]
      user.save
    end
    flash[:info] = "The selected users have been updated to the '#{params[:new_role]}' role"
    params.delete :new_role
    redirect_to donors_path
  end

  private

  def donors_scope
    scope = Donor.fuzzy_search(params[:search])

    if params[:donated_last_year] && !params[:last_year_from].blank? && !params[:last_year_to].blank?
      scope = scope.where("donated_last_year_in_dkk BETWEEN #{params[:last_year_from].to_i} AND #{params[:last_year_to].to_i}")
    end

    if !params[:role].blank?
      scope = scope.where("role LIKE ?", "%#{params[:role]}%")
    end

    return scope
  end

end
