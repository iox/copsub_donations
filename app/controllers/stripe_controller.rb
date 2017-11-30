class StripeController < ApplicationController

  skip_before_filter :authenticate
  protect_from_forgery :except => [:donation]
  before_filter :override_cors_limitations

  def subscribe
    donor = Donor.where(user_email: params["email"]).first
    donor.create_stripe_customer
    donor.update_attribute(:stripe_card_expiration_date, Date.parse("#{params['card']['exp_year']}-#{params['card']['exp_month']}-01"))

    Stripe::Subscription.create(
      :customer => donor.stripe_customer_id,
      :plan => params["plan"],
      :source => params["id"]
    )
    
    # DonorMailer.thank_you(donor, true).deliver
    donor.send_thank_you_mailchimp_email

    render status: 200, json: "OK".to_json
  end

  def donate
    donor = Donor.where(user_email: params["email"]).first

    temp = {
      :amount => donor.selected_amount*100, # Stripe expects the amount in cents. 20€ => 2000
      :currency => "eur",
      :description => "Copenhagen Suborbitals donation",
      :source => params["id"]
    }
    
    Rails.logger.info temp.inspect

    Stripe::Charge.create(
      temp
    )
    
    DonorMailer.thank_you(donor, false).deliver

    render status: 200, json: "OK".to_json
  end
end