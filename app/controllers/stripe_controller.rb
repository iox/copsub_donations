class StripeController < ApplicationController

  skip_before_filter :authenticate
  protect_from_forgery :except => [:webhook]
  before_filter :override_cors_limitations


  # RECURRING PAYMENT ACTIONS
  def new_recurring_payment_session
    # Stripe no longer supports manually setting the price id for a certain plan
    # This is a workaround
    mach1_price_id_development = "price_1IuxHYHZGxJbl38FlPKw6dvU"
    mach1_price_id_production = "price_1IuxGrHZGxJbl38Fhnkr0Scm"
    if params['plan_id'] == 'mach1'
      params['plan_id'] = Rails.env.production? ? mach1_price_id_production : mach1_price_id_development
    end


    Stripe.api_key = ENV['STRIPE_CSS_API_KEY']
    session = Stripe::Checkout::Session.create(
      success_url: "#{request.base_url}/api/stripe/recurring_payment_success?session_id={CHECKOUT_SESSION_ID}",
      cancel_url: 'https://www.copenhagensuborbitals.com/support-us',
      payment_method_types: ['card'],
      mode: 'subscription',
      line_items: [{
        quantity: 1,
        price: params['plan_id'], # this will be either 'mach1', 'mach2' or 'mach3'
      }],
    )
    render status: 200, json: {session_id: session.id}
  end

  def recurring_payment_success
    Stripe.api_key = ENV['STRIPE_CSS_API_KEY']
    customer_id = Stripe::Checkout::Session.retrieve(params[:session_id]).customer
    email = Stripe::Customer.retrieve(customer_id).email

    donor = Donor.find_by_any_email(email).first || Donor.create(user_email: email)

    DonorMailer.thank_you(donor, true).deliver
    
    redirect_to 'https://www.copenhagensuborbitals.com/thank_you'
  end



  # ONETIME PAYMENT ACTIONS
  def new_onetime_payment_session
    Stripe.api_key = ENV['STRIPE_CS_API_KEY']
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
      success_url: "#{request.base_url}/api/stripe/onetime_payment_success?session_id={CHECKOUT_SESSION_ID}",
      cancel_url: 'https://www.copenhagensuborbitals.com/support-us',
    )

    render status: 200, json: {session_id: session.id}
  end


  def onetime_payment_success
    Stripe.api_key = ENV['STRIPE_CS_API_KEY']

    Rails.logger.info params.inspect

    session = Stripe::Checkout::Session.retrieve(params[:session_id])
    email = session.customer_details.email
    
    donor = Donor.find_by_any_email(email).first || Donor.create(user_email: email)

    DonorMailer.thank_you(donor, false).deliver
    
    redirect_to 'https://www.copenhagensuborbitals.com/thank_you'
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