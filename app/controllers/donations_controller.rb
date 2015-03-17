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
    @imported_donations = []
    @already_existing_donations = []
    @message = ""
    if params[:csv]
      CSV.foreach(params[:csv].path, headers: true, col_sep: ';', encoding: 'ISO-8859-1') do |row|
        donation = row.to_hash
        existing_donation = Donation.where(:donation_method => 'bank', :bank_reference => donation["Tekst"], :donated_at => donation["Bogført"].to_time, :amount => donation["Beløb"].to_f).first
        if existing_donation
          @already_existing_donations << donation
        else
          @imported_donations << donation
          donation = Donation.new(
            :bank_reference => donation["Tekst"],
            :donated_at => donation["Bogført"],
            :amount => donation["Beløb"],
            :currency => 'DKK',
            :donation_method => 'bank'
          )
          if !donation.save
            logger.info donation.errors.inspect
          else
            @message += "<br/> - Donation #{donation.id}, amount #{donation.amount}, bank reference #{donation.bank_reference} imported"
            @message += "<strong>User found: #{donation.wordpress_user_id}</strong>" if donation.wordpress_user_id
          end
        end
      end
    end
  end

  def show
    @donation = Donation.find(params[:id])
    @user = @donation.user
    @search_value = params[:search] || @donation.email
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
    redirect_to '/'
  end

  def index
    @search = Donation.search(params[:q])
    @donations = @search.result.paginate(:page => params[:page])
  end

  private

  def last_imported_donation_id
    last = Donation.where("seamless_donation_id IS NOT NULL").order(:seamless_donation_id).last
    last ? last.seamless_donation_id : 0
  end

end
