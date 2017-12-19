class FrontController < ApplicationController

  hobo_controller

  def index; end

  def summary
    if !current_user.administrator?
      redirect_to user_login_path
    end
  end

  def search
    if params[:query]
      site_search(params[:query])
    end
  end
  
  def report

    params[:start_date] ||= I18n.l(Date.today - 1.month - 1.day)
    params[:end_date] ||= I18n.l(Date.today - 1.day)
    @start_date = params[:start_date].to_date
    @end_date = params[:end_date].to_date
    
    last_bank_donation_date = Donation.where(donation_method: 'bank').order("donated_at asc").last.donated_at.to_date
    if @end_date > last_bank_donation_date
      @alert = "Warning: The last registered bank donation occurred on #{I18n.l(last_bank_donation_date)}. This means that no bank statements have been imported into the donations app since then. This report could show incorrect lost regular donors. Please import the latest bank statement to update this report."
    end
    
    @new_regular_donors = Donor.where("((role = 'recurring_supporter' OR selected_donor_type = 'supporter') AND first_donated_at >= ? AND first_donated_at <= ?) OR (role = 'inactive_supporter' AND last_donated_at >= ? AND last_donated_at <= ?)", @start_date, @end_date, @start_date, @end_date).order("first_donated_at")

    @lost_regular_donors = Donor.where("stopped_regular_donations_date IS NOT NULL AND stopped_regular_donations_date >= ? AND stopped_regular_donations_date <= ?", @start_date, @end_date).order("stopped_regular_donations_date desc")
    
    @current_monthly_income_regular_donors = Donor.where("role = 'recurring_supporter'")
    
    @regular_donations_monthly = Donation.where(other_income: false).where("category_id != 5").where("donated_at > ?", @start_date - 1.year).order("donated_at").group("date_format(donated_at, '%M %Y')").sum(:amount_in_dkk)
    @onetime_donations_monthly = Donation.where(other_income: false).where("category_id  = 5").where("donated_at > ?", @start_date - 1.year).order("donated_at").group("date_format(donated_at, '%M %Y')").sum(:amount_in_dkk)
    
    @onetime_donations = Donation.where(other_income: false).where(category_id: 5).where("donated_at >= ? AND donated_at <= ?", @start_date, @end_date)
  end

end
