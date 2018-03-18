class StripeController < ApplicationController

  skip_before_filter :authenticate
  protect_from_forgery :except => [:donation, :webhook]
  before_filter :override_cors_limitations

  def subscribe
    donor = Donor.where(user_email: params["email"]).first || Donor.new(user_email: params["email"])
    donor.create_stripe_customer
    donor.update_attribute(:stripe_card_expiration_date, Date.parse("#{params['card']['exp_year']}-#{params['card']['exp_month']}-01"))

    Stripe::Subscription.create(
      :customer => donor.stripe_customer_id,
      :plan => params["plan"],
      :source => params["id"]
    )
    
    # DonorMailer.thank_you(donor, true).deliver
    # donor.send_thank_you_mailchimp_email

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