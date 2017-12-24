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
    
    @started_donating = Donation.where(first_donation_in_series: true).where("donated_at >= ? AND donated_at <= ?", @start_date, @end_date).order("donated_at DESC")
    @stopped_donating = Donation.where(last_donation_in_series: true).where("stopped_donating_date >= ? AND stopped_donating_date <= ?", @start_date, @end_date).order("stopped_donating_date DESC")
    
    @last_month_recurring_donations = Donation.where(other_income: false).where("category_id != 5").where("donated_at >= ? AND donated_at <= ?", (Time.now - 1.month).beginning_of_month, (Time.now - 1.month).end_of_month)
    
    @regular_donations_monthly = Donation.where(other_income: false).where("category_id != 5").where("donated_at >= ?", (@start_date - 1.year).beginning_of_month).where("donated_at < ?", Time.now.beginning_of_month).order("donated_at").group("date_format(donated_at, '%M %Y')").sum(:amount_in_dkk)
    @onetime_donations_monthly = Donation.where(other_income: false).where("category_id  = 5").where("donated_at >= ?", (@start_date - 1.year).beginning_of_month).where("donated_at < ?", Time.now.beginning_of_month).order("donated_at").group("date_format(donated_at, '%M %Y')").sum(:amount_in_dkk)
    @started_donating_monthly = Donation.where(other_income: false).where(first_donation_in_series: true).where("donated_at >= ?", (@start_date - 1.year).beginning_of_month).where("donated_at < ?", Time.now.beginning_of_month).order("donated_at").group("date_format(donated_at, '%M %Y')").sum(:amount_in_dkk)
    @stopped_donating_monthly = Donation.where(other_income: false).where(last_donation_in_series: true).where("stopped_donating_date >= ?", (@start_date - 1.year).beginning_of_month).where("stopped_donating_date < ?", Time.now.beginning_of_month).order("stopped_donating_date").group("date_format(stopped_donating_date, '%M %Y')").sum(:amount_in_dkk)
    
    @onetime_donations = Donation.where(other_income: false).where(category_id: 5).where("donated_at >= ? AND donated_at <= ?", @start_date, @end_date).order("donated_at desc")
  end

end
