class DonorsController < ApplicationController

  hobo_model_controller

  auto_actions :all

  skip_before_filter :authenticate, :only => [:new_bank_donor, :new_donor]
  protect_from_forgery :except => [:new_bank_donor, :new_donor]

  # POST /api/new_bank_donor
  # TODO: Remove this method, after the new website is online
  def new_bank_donor
    donor = Donor.find_by_user_email(params["email"]) || Donor.new(
      user_email: params["email"],
      role: "subscriber")
    donor.save

    donor.paymentid = "donor#{donor.id}"
    donor.save

    repeating = params["repeating"] == "1"
    DonorMailer.bank_donation_instructions(donor, repeating).deliver

    render text: donor.paymentid
  end

  # POST /api/new_donor
  # This endpoint receives the data from the donations flow, creates a new donor and return its donor ID
  def new_donor
    override_cors_limitations

    donor = Donor.find_by_user_email(params["email"]) || Donor.create(
      user_email: params["email"],
      # They are just subscribers, until a payment has been registered
      role: "subscriber",
      country: params["country"],
      donation_method: params[:donation_method]
    )

    donor.paymentid = "donor#{donor.id}"
    # "supporter" or "one_time", depending on what the donor selected in the donations flow
    donor.selected_donor_type = params[:selected_donor_type]
    # we store how much the donor wished to donate, in case something fails and we need to send a reminder
    donor.selected_amount = params[:selected_amount].to_i

    donor.save

    if params[:donation_method] == 'bank'
      DonorMailer.bank_donation_instructions(donor, repeating).deliver
    end

    render text: donor.id
  end

  def index
    params[:search] ||= ""
    params[:sort] ||= "id"
    params[:direction] ||= "asc"

    @donors = donors_scope.order("#{params[:sort]} #{params[:direction]}").paginate(:page => params[:page])
    @fields = "id, user_email, first_name, last_name, city, country, paymentid, paypalid, "
    @fields += 'first_donated_at, ' if params[:donation_date] == 'first_donated_at'
    @fields += 'last_donated_at, ' if params[:donation_date] == 'last_donated_at' || params[:donated_last_days].present?
    @fields += 'last_paypal_failure, ' if params[:donation_date] == 'last_paypal_failure'
    @fields += "role, "
    @fields += 'mailchimp_status, ' if params[:mailchimp_status].present?
    @fields += 'donation_method, ' if params[:donation_method].present?
    @fields += 'donated_total, ' if params[:donated_total]
    @fields += 'donated_last_year_in_dkk' if params[:donated_last_year]
    @fields += 'number_of_donations' if params[:number_of_donations]

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

  def mailchimp_email_preview
    gibbon = Gibbon::Request.new
    @automations = gibbon.automations.retrieve["automations"]
    @automation_id = params[:automation_id] || @automations.first['id']
    @emails = gibbon.automations(@automation_id).emails.retrieve["emails"]


    if request.xhr?
      hobo_ajax_response
      return
    end

    unless params[:search]
      flash[:error] = "You need to filter the users before sending a mailchimp email"
      redirect_to :back
    end

    @donors = donors_scope
  end

  def send_mailchimp_email
    if params[:emails].blank?
      flash[:error] = "No users were selected"
      redirect_to :back and return
    end

    unless Rails.env.production?
      flash[:notice] = "Emails were not sent, because we are not running in production"
      redirect_to :back and return
    end

    gibbon = Gibbon::Request.new
    email_details = gibbon.automations(params[:automation_id]).emails(params[:email_id]).retrieve
    email_subject = (email_details && email_details["settings"]) ? email_details["settings"]["title"] : nil

    for email in params[:emails]
      begin
        gibbon.automations(params[:automation_id]).emails(params[:email_id]).queue.create(body: {email_address: email})
        flash[:notice] ||= ""
        flash[:notice] += " Email sent to #{email}."
        EmailLog.create(email: email, subject: email_subject) if email_subject
      rescue => e
        flash[:error] ||= ""
        flash[:error] += " Mailchimp returned an error with #{email}: " + e.detail.inspect
      end
    end

    redirect_to :back
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

    if params[:donation_date].in?(['first_donated_at', 'last_donated_at', 'last_paypal_failure'])  && !params[:donation_date_from].blank? && !params[:donation_date_to].blank?
      scope = scope.where("#{params[:donation_date]} BETWEEN ? AND ?", params[:donation_date_from].to_date, params[:donation_date_to].to_date)
    end

    if params[:number_of_donations]
      scope = scope.where("number_of_donations >= ?", params[:number_of_donations])
    end

    return scope
  end

end
