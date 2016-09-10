class DonationsController < ApplicationController

  hobo_model_controller

  auto_actions :all

  before_filter :require_admin, :except => [:index, :show]

  def require_admin
    redirect_to '/' unless current_user.administrator?
  end

  def import_donations_from_wordpress
    @result = ImportDonationsFromWordpress.new.import
    render 'import_donations_result'
  end

  def import_donations_from_csv
    if params[:csv]
      @result = ImportDonationsFromCSV.new(params[:csv]).import
      render 'import_donations_result'
    else
      redirect_to '/import'
    end
  end

  def show
    @donation = Donation.find(params[:id])
    @user = @donation.user
    @search_value = params[:search] || @donation.default_search_value
    @users_count = Donor.fuzzy_search(@search_value).count
    @users = Donor.fuzzy_search(@search_value).limit(20)
    @related_unassigned_donations = AssignUserManually.new(@donation).related_unassigned_donations
    if request.xhr?
      hobo_ajax_response
    end
  end

  def assign_donation
    @donation = Donation.find params[:donation_id]
    @user = Donor.find params[:user_id]
    AssignUserManually.new(@donation).assign(@user)
    flash[:notice] = "Donation #{@donation.id} was assigned to #{@user.id} (#{@user.user_email})"
    redirect_to '/donations?q[user_assigned_eq]=f'
  end

  def unassign_donation
    @donation = Donation.find params[:donation_id]
    if @donation.user
      UnassignUser.new(@donation).unassign
      flash[:notice] = "Donation #{@donation.id} has been unassigned. Now you can assign it to another user"
      redirect_to :back
    else
      flash[:error] = "Donation #{@donation.id} had no user assigned, so it could not be unassigned."
      redirect_to :back
    end
  end

  def index
    params[:search] ||= ""
    params[:sort] ||= "id"
    params[:direction] ||= "desc"
    params[:other_income] ||= "no"

    scope = donations_scope
    @donations = scope.order("#{params[:sort]} #{params[:direction]}").paginate(:page => params[:page])
    @total = scope.sum(:amount_in_dkk)

    respond_to do |format|
      format.html
      format.text { render csv: scope.all }
    end
  end

  private

  def donations_scope
    scope = Donation

    if params[:email].present?
      scope = scope.where("email LIKE ?", "%#{params[:email]}%")
    end

    if params[:bank_reference].present?
      scope = scope.where("bank_reference LIKE ?", "%#{params[:bank_reference]}%")
    end

    if params[:currency].present?
      scope = scope.where(currency: params[:currency])
    end

    if params[:donation_method].present?
      scope = scope.where(donation_method: params[:donation_method])
    end

    if params[:amount_in_dkk] && !params[:amount_in_dkk_from].blank? && !params[:amount_in_dkk_to].blank?
      scope = scope.where("amount_in_dkk BETWEEN #{params[:amount_in_dkk_from].to_i} AND #{params[:amount_in_dkk_to].to_i}")
    end

    if params[:role].present?
      scope = scope.joins(:donor).where("donors.role = ?", params[:role])
    end

    if params[:user_assigned].present?
      scope = scope.where(user_assigned: params[:user_assigned] == 'yes')
    end

    if params[:other_income].present?
      scope = scope.where(other_income: params[:other_income] == 'yes')
    end

    if params[:category_id].present?
      scope = scope.where(category_id: params[:category_id])
    end

    if params[:donated_at] && !params[:donated_at_from].blank? && !params[:donated_at_to].blank?
      scope = scope.where("donated_at BETWEEN ? AND ?", params[:donated_at_from].to_date, params[:donated_at_to].to_date)
    end

    return scope
  end

end
