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

  def find_duplicated_donors
    emails = Hash.new
    suspects = []
    @duplicated_emails = []

    for column in %w{user_email paypalid}
      emails[column] = Donor.where("#{column} IS NOT NULL && #{column} != '' && #{column} != '0'").order(column.to_sym).pluck(column.to_sym).collect(&:strip).sort
    end

    for email in emails["user_email"]
      suspects << email if (emails["user_email"].count(email) > 1) || emails["paypalid"].include?(email)
    end

    for email in emails["paypalid"]
      suspects << email if (emails["paypalid"].count(email)   > 1) || emails["user_email"].include?(email)
    end

    for suspect in suspects.uniq
      donors = Donor.where("user_email LIKE ? OR paypalid LIKE ?", "%#{suspect}%", "%#{suspect}%")
      @duplicated_emails << suspect if donors.count > 1
    end

    if @duplicated_emails.size > 0
      @first_duplicated_donors = Donor.where("user_email LIKE ? OR paypalid LIKE ?", "%#{@duplicated_emails.first}%", "%#{@duplicated_emails.first}%")
    end
  end

  def delete_duplicated_donor
    duplicated = Donor.find(params[:id])
    other_donor = Donor.where("user_email LIKE ? OR paypalid LIKE ?", "%#{params[:email]}%", "%#{params[:email]}%").where("id != ?", params[:id]).first
    duplicated.donations.update_all("donor_id = #{other_donor.id}")
    other_donor.update_amount_donated_last_year!
    if duplicated.destroy
      flash[:notice] = "The duplicated donor #{duplicated.id} has been deleted, and all his donations have been assigned to the donor #{other_donor.id}. The common email was #{params[:email]}."
      redirect_to '/find_duplicated_donors'
    else
      flash[:error] = "The donor #{duplicated.id} could not be deleted"
      redirect_to '/find_duplicated_donors'
    end
  end

  private

  def donors_scope
    scope = Donor.fuzzy_search(params[:search])

    if params[:donated_last_year] && !params[:donated_last_year_from].blank? && !params[:donated_last_year_to].blank?
      scope = scope.where("donated_last_year_in_dkk BETWEEN #{params[:donated_last_year_from].to_i} AND #{params[:donated_last_year_to].to_i}")
    end

    if params[:donated_total] && !params[:donated_total_from].blank? && !params[:donated_total_to].blank?
      scope = scope.where("donated_total BETWEEN #{params[:donated_total_from].to_i} AND #{params[:donated_total_to].to_i}")
    end

    if params[:first_donated_at] && !params[:first_donated_at_from].blank? && !params[:first_donated_at_to].blank?
      scope = scope.where("first_donated_at BETWEEN ? AND ?", params[:first_donated_at_from].to_date, params[:first_donated_at_to].to_date)
    end

    if params[:last_donated_at] && !params[:last_donated_at_from].blank? && !params[:last_donated_at_to].blank?
      scope = scope.where("last_donated_at BETWEEN ? AND ?", params[:last_donated_at_from].to_date, params[:last_donated_at_to].to_date)
    end

    if params[:mailchimp_status].present?
      scope = scope.where(mailchimp_status: params[:mailchimp_status])
    end

    if params[:donation_method].present?
      scope = scope.where(donation_method: params[:donation_method])
    end

    if params[:role].present?
      scope = scope.where(role: params[:role])
    end

    if params[:donated_last_days].present?
      scope = scope.where("last_donated_at > ?", Date.today - params[:donated_last_days].to_i)
    end

    return scope
  end

end
