class DonationsController < ApplicationController

  hobo_model_controller

  auto_actions :all

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
    @search_value = params[:search] || @donation.email || @donation.bank_reference.gsub(/[^0-9]/, '')
    @users_count = WordpressUser.fuzzy_search(@search_value).count
    @users = WordpressUser.fuzzy_search(@search_value).limit(20)
    @related_unassigned_donations = AssignUserManually.new(@donation).related_unassigned_donations
    if request.xhr?
      hobo_ajax_response
    end
  end

  def assign_donation
    @donation = Donation.find params[:donation_id]
    @user = WordpressUser.find params[:user_id]
    AssignUserManually.new(@donation).assign(@user)
    flash[:notice] = "Donation #{@donation.id} was assigned to #{@user.id} (#{@user.user_email})"
    redirect_to '/donations?q[user_assigned_eq]=f'
  end

  def index
    scope = params[:other_income] ? Donation.other_income : Donation.not_other_income
    @search = scope.search(params[:q])
    @total = @search.result.sum(:amount_in_dkk)
    @donations = @search.result.paginate(:page => params[:page])
  end

end
