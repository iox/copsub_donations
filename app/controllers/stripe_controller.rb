class StripeController < ApplicationController

  skip_before_filter :authenticate
  protect_from_forgery :except => [:donation]
  before_filter :override_cors_limitations

  def subscribe
    #params = {"id"=>"tok_19vRDeHZGxJbl38FGBVWHXj4", "object"=>"token", "card"=>{"id"=>"card_19vRDeHZGxJbl38FICT2pKEQ", "object"=>"card", "address_city"=>"", "address_country"=>"", "address_line1"=>"", "address_line1_check"=>"", "address_line2"=>"", "address_state"=>"", "address_zip"=>"", "address_zip_check"=>"", "brand"=>"Visa", "country"=>"US", "cvc_check"=>"pass", "dynamic_last4"=>"", "exp_month"=>"12", "exp_year"=>"2019", "funding"=>"credit", "last4"=>"4242", "name"=>"ignacio+434@gmail.com", "tokenization_method"=>""}, "client_ip"=>"80.167.164.26", "created"=>"1489065734", "email"=>"ignacio+434@gmail.com", "livemode"=>"false", "type"=>"card", "used"=>"false"}

    donor = Donor.where(user_email: params["email"]).first
    donor.create_stripe_customer
    donor.update_attribute(:stripe_card_expiration_date, Date.parse("#{params['card']['exp_year']}-#{params['card']['exp_month']}-01"))

    Stripe::Subscription.create(
      :customer => donor.stripe_customer_id,
      :plan => params["plan"],
      :source => params["id"]
    )

    render status: 200, json: "OK".to_json
  end

  def donate
    donor = Donor.where(email: params["email"]).first
    donor.create_stripe_customer

    Stripe::Charge.create(
      :amount => donor.selected_amount,
      :currency => "eur",
      :description => "Copenhagen Suborbitals donation",
      :source => params["id"],
      :customer => donor.stripe_customer_id
    )

    render status: 200, json: "OK".to_json
  end
end