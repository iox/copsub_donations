class WordpressUsersController < ApplicationController

  include HoboPermissionsHelper

  def show
    @wordpress_user = WordpressUser.with_all_fields.find(params[:id])
  end

  def index
    params[:search] ||= ""
    scope = WordpressUser.with_all_fields.fuzzy_search(params[:search])

    if params[:last_year_less_than]
      # Add an additional JOIN to filter by the amount donated last year
      scope = scope.joins("LEFT OUTER JOIN copsub_donations.donations ON #{PREFIX}users.id = copsub_donations.donations.wordpress_user_id AND copsub_donations.donations.donated_at > '#{(Date.today-1.year).to_time.to_s(:db)}'").group("#{PREFIX}users.id").
              where("#{PREFIX}capabilities.meta_value NOT LIKE '%subscriber%'").
              having("IFNULL(sum(copsub_donations.donations.amount_in_dkk),0) < #{params[:last_year_less_than].to_i}")
    end

    @wordpress_users = scope.paginate(:page => params[:page])

    respond_to do |format|
      format.html
      format.text { render csv: scope, only: [:ID, :user_email, :user_login, :display_name], add_methods: [:user_adress, :city, :country, :user_phone, :paymentid, :paypal_id, :role] }
    end
  end

end
