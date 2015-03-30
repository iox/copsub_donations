class DonationsController < ApplicationController

  hobo_model_controller

  auto_actions :all

  def import_donations_from_wordpress
    new_donations = SeamlessDonation.where("id > #{last_imported_donation_id}")
    @message = "#{new_donations.count} donations imported from Wordpress:"
    new_donations.find_each(batch_size: 100) do |donation|
      donation = Donation.new(
        :seamless_donation_id => donation.id,
        :amount => donation.amount,
        :donated_at => donation.post_date,
        :currency => donation.currency,
        :email => donation.email,
        :donation_method => 'paypal'
      )
      if !donation.save
        logger.info donation.errors.inspect
      else
        @message += "<br/> - Donation #{donation.id}, amount #{donation.amount}, email #{donation.email} imported"
        @message += "<strong>User found: #{donation.wordpress_user_id}</strong>" if donation.wordpress_user_id
      end
    end
  end

  def import_donations_from_csv
    if params[:csv]
      @result = ImportDonationsFromCSV.new(params[:csv]).import
    end
  end

  def show
    @donation = Donation.find(params[:id])
    @user = @donation.user
    @search_value = params[:search] || @donation.email || @donation.bank_reference.gsub(/[^0-9]/, '')
    @users = WordpressUser.fuzzy_search(@search_value)
    if request.xhr?
      hobo_ajax_response
    end
  end

  def assign_donation
    @donation = Donation.find params[:donation_id]
    @user = WordpressUser.find params[:user_id]
    @donation.assign(@user)
    flash[:notice] = "Donation #{@donation.id} was assigned to #{@user.id} (#{@user.user_email})"
    redirect_to @donation
  end

  def index
    @search = Donation.search(params[:q])
    @total = @search.result.sum(:amount_in_dkk)
    @donations = @search.result.paginate(:page => params[:page])
  end

  private

  def last_imported_donation_id
    last = Donation.where("seamless_donation_id IS NOT NULL").order(:seamless_donation_id).last
    last ? last.seamless_donation_id : 0
  end

end
