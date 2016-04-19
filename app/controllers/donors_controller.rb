class DonorsController < ApplicationController

  hobo_model_controller

  auto_actions :all

  skip_before_filter :authenticate, :only => [:new_bank_donor]
  protect_from_forgery :except => [:new_bank_donor]

  def new_bank_donor
    donor = Donor.find_by_user_email(params["email"]) || Donor.new(
      user_email: params["email"],
      user_login: params["email"],
      role: "subscriber")
    donor.save

    donor.paymentid = "donor#{donor.id}"
    donor.save

    repeating = params["repeating"] == "1"
    DonorMailer.bank_donation_instructions(donor, repeating).deliver

    render text: donor.paymentid
  end

  def index
    params[:search] ||= ""
    params[:sort] ||= "id"
    params[:direction] ||= "asc"

    @donors = donors_scope.order("#{params[:sort]} #{params[:direction]}").paginate(:page => params[:page])

    respond_to do |format|
      format.html
      format.text { render csv: donors_scope.all }
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

    if params[:first_donation] && !params[:first_donation_from].blank? && !params[:first_donation_to].blank?
      scope = scope.where("first_donation BETWEEN ? AND ?", params[:first_donation_from].to_date, params[:first_donation_to].to_date)
    end

    if params[:mailchimp_status].present?
      scope = scope.where(mailchimp_status: params[:mailchimp_status])
    end

    if !params[:role].blank?
      scope = scope.where("role LIKE ?", "%#{params[:role]}%")
    end

    return scope
  end

end
