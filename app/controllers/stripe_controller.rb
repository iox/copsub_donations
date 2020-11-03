class StripeController < ApplicationController

  skip_before_filter :authenticate
  protect_from_forgery :except => [:donation, :webhook]
  before_filter :override_cors_limitations

  def subscribe
    donor = Donor.find_by_any_email(params["email"]).first || Donor.new(user_email: params["email"])
    donor.create_stripe_customer
    donor.update_attribute(:stripe_card_expiration_date, Date.parse("#{params['card']['exp_year']}-#{params['card']['exp_month']}-01"))

    begin
      Stripe::Subscription.create(
        :customer => donor.stripe_customer_id,
        :plan => params["plan"],
        :source => params["id"]
      )
    rescue Stripe::CardError => e
      # Since it's a decline, Stripe::CardError will be caught
      body = e.json_body
      err  = body[:error]
      
      Rails.logger.info "Stripe::CardError"
      Rails.logger.info err.inspect
      
      render status: 500, json: e.json_body and return
    end
    
    DonorMailer.thank_you(donor, true).deliver

    render status: 200, json: "OK".to_json
  end



  def new_onetime_payment_session
    session = Stripe::Checkout::Session.create(
      payment_method_types: ['card'],
      line_items: [{
        name: "Copenhagen Suborbitals donation",
        description: 'One time donation',
        images: ['https://copenhagensuborbitals.com/wp-content/uploads/2017/02/header_supportus_1600x800_jl_v2.jpg'],
        amount: (params["selected_amount"].to_i)*100,
        currency: 'usd',
        quantity: 1,
      }],
      success_url: 'http://localhost:3016/api/stripe/onetime_payment_success?session_id={CHECKOUT_SESSION_ID}',
      cancel_url: 'https://www.copenhagensuborbitals.com/support-us',
    )

    render status: 200, json: {session_id: session.id}
  end


  def onetime_payment_success
    # TODO: Get the email via the API using the session id
    email = Stripe::Checkout::Session.find(params[:session_id]).email

    donor = Donor.find_by_any_email(email).first || Donor.create(user_email: email)

    DonorMailer.thank_you(donor, false).deliver
    
    redirect_to 'https://www.copenhagensuborbitals.com/thank_you'
  end







  
  # TODO: This API endpoint is deprecated due to the SCA rules
  def donate
    donor = Donor.find_by_any_email(params["email"]).first || Donor.create(user_email: params["email"])

    charge = {
      :amount => (params["selected_amount"].to_i)*100, # Stripe expects the amount in cents. 20€ => 2000
      :currency => "usd",
      :description => "Copenhagen Suborbitals donation",
      :source => params["id"]
    }
    
    Rails.logger.info charge.inspect

    begin
      Stripe::Charge.create(charge)
    rescue Stripe::CardError => e
      # Since it's a decline, Stripe::CardError will be caught
      body = e.json_body
      err  = body[:error]
      
      Rails.logger.info "Stripe::CardError"
      Rails.logger.info err.inspect
      
      render status: 500, json: e.json_body and return
    end
    
    DonorMailer.thank_you(donor, false).deliver

    render status: 200, json: "OK".to_json
  end
  
  
  def webhook
    # TODO: webhook is disabled temporarily. For now, we use a rake task to import Stripe payments
    
    # payload = request.body.read
    # sig_header = request.env['HTTP_STRIPE_SIGNATURE']
    # event = nil
  
    # begin
    #   event = Stripe::Webhook.construct_event(
    #     payload, sig_header, ENV['STRIPE_ENDPOINT_SECRET']
    #   )
    # rescue JSON::ParserError => e
    #   # Invalid payload
    #   render plain: 'INVALID PAYLOAD', status: 400
    #   return
    # rescue Stripe::SignatureVerificationError => e
    #   # Invalid signature
    #   render plain: 'INVALID SIGNATURE', status: 400
    #   return
    # end
  
    # # Do something with event
    
    # logger.info "Stripe Event received"
    # logger.info event.inspect.to_s
    
    # if event.type == 'invoice.payment_succeeded'
    #   logger.info event.inspect
      
    #   customer = Stripe::Customer.retrieve(event.data.object.customer)
    #   logger.info customer.inspect
    # end
    
  
    render text: 'SUCCESS'
  end
end