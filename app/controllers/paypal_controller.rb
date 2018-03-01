class PaypalController < ApplicationController



  skip_before_filter :authenticate
  protect_from_forgery :except => [:ipn, :execute_billing_agreement]
  before_filter :override_cors_limitations


  include PayPal::SDK::REST

  include OffsitePayments::Integrations
  require 'money'
  # OffsitePayments.mode = :test

  def ipn
    log = "Paypal IPN received. params:\n"
    log += params.inspect.to_s

    notify = Paypal::Notification.new(request.raw_post)
    log += notify.inspect.to_s

    if notify.acknowledge
      store_paypal_event(notify)

      notify.complete? ? store_donation(notify) : (log += "\nNotification is not complete, please investigate".to_s)
    else
      log += "\nFailed to verify Paypal's notification, please investigate"
    end

    logger.error log
    ActionMailer::Base.mail(from: 'no-reply@copsub.com', to: 'rasmusagdestein.e9187@m.evernote.com', subject: 'Donations app received a Paypal IPN @CopSub_Log', body: log).deliver
    head 200
  end
  
  
  
  
  
  
  def generate_payment_token
    
    donor = Donor.find_by_user_email(params["email"]) || Donor.create(
      first_name: params["name"].split(' ',2)[0],
      last_name: params["name"].split(' ',2)[1],
      user_email: params["email"],
      # They are just subscribers, until a payment has been registered
      role: "subscriber",
      country: params["country"]
    )
    

    donor.paymentid = "donor#{donor.id}"
    # "supporter" or "one_time", depending on what the donor selected in the donations flow
    donor.selected_donor_type = params[:selected_donor_type]
    # we store how much the donor wished to donate, in case something fails and we need to send a reminder
    donor.selected_amount = params[:selected_amount].to_i
    # Store the donation method and the date when the user filled in the donation form    
    donor.donation_method = "paypal"
    donor.filled_donation_form_date = Date.today

    if params[:newsletter_opt_in] && params[:newsletter_opt_in] == 'on'
      donor.subscribe_to_mailchimp_list
      donor.mailchimp_status = "subscribed"
    else
      donor.mailchimp_status = "unsubscribed"
    end

    donor.save
    
    
    
    plan = Plan.new({
      "name" => "Copenhagen Suborbitals Support Group - #{params['plan'].upcase}",
      "description" => "Copenhagen Suborbitals Support Group - #{params['plan'].upcase}",
      "type" => "INFINITE",
      "payment_definitions" => [
          {
              "name" => "Regular Payments",
              "type" => "REGULAR",
              "frequency" => "MONTH",
              "frequency_interval" => "1",
              "amount" => {
                  "value" => "#{params['selected_amount']}",
                  "currency" => "EUR"
              },
              "cycles" => "0",
          }
      ],
      "merchant_preferences" => {
          "return_url" => "http://www.return.com",
          "cancel_url" => "http://www.cancel.com",
          "auto_bill_amount" => "YES",
          "initial_fail_amount_action" => "CONTINUE",
          "max_fail_attempts" => "0"
      }
    })
    
    plan.create
    
    
    patch = PayPal::SDK::REST::Patch.new
    patch.op = "replace"
    patch.path = "/"
    patch.value = { :state => "ACTIVE" }
    plan.update(patch)
        
    
    
    agreement = Agreement.new({
      "name" => "Copenhagen Suborbitals Support Group - #{params['plan'].upcase}",
      "description" => "Copenhagen Suborbitals Support Group - #{params['plan'].upcase}",
      "start_date" => (Time.now + 30.minutes).iso8601,
      "payer" => {
          "payment_method" => "paypal"
      },
    })
    agreement.plan =  Plan.new( :id => plan.id )
    
    if agreement.create
      render json: {
        agreement_id: agreement.links.find { |l| l.rel == 'approval_url' }.href.split("token=")[1],     # Agreement Id
        plan_id: plan.id}
    else
      render json: agreement.error, status: 500  # Error Hash
    end
    
    
    # # Build Payment object for single donation
    # @payment = Payment.new({
    #   :intent => "sale",
    #   :redirect_urls => {
    #     :return_url => "http://example.com/your_redirect_url.html",
    #     :cancel_url => "http://example.com/your_cancel_url.html"
    #   },
    #   :payer => {
    #     :payment_method => "paypal"
    #   },
    #   :transactions => [{
    #     :item_list => {
    #       :items => [{
    #         :name => "item",
    #         :sku => "item",
    #         :price => "1",
    #         :currency => "USD",
    #         :quantity => 1 }]},
    #     :amount => {
    #       :total => "1.00",
    #       :currency => "USD" },
    #     :description => "This is the payment transaction description." }]})
    
    
    
    # # Create Payment and return the status(true or false)
    # if @payment.create
    #   render json: @payment.id     # Payment Id
    # else
    #   render json: @payment.error, status: 500  # Error Hash
    # end
    
    
    
    
  end
  
  
  
  def execute_billing_agreement
    agreement = PayPal::SDK::REST::Agreement.new(token: params[:token])
    agreement.execute
    
    # TODO: If the execution of the agreement worked fine, it means that the user has started a regular donation
    # In this case, we need to send him or her an a welcome email
    # donor = Donor.where(email: agreement.email)
    # donor.send_thank_you_mailchimp_email if donor
    
    render json: agreement
  end
  
  
  
  
  
  
  
  
  
  
  
  

  private

  def store_paypal_event(notify)
    clean_params = params.inject({}) { |h, (k, v)| h[k] = v.force_encoding('ISO-8859-1').encode('UTF-8'); h }
    PaypalEvent.create(clean_params)
  end

  def store_donation(notify)
    begin
      donated_at = DateTime.strptime(params["payment_date"], "%H:%M:%S %b %e, %Y %Z").new_offset(0)
    rescue
      donated_at = Time.now
    end
    
    if Donation.where(paypal_transaction_id: notify.transaction_id).count > 0
      logger.info "The Paypal transaction #{notify.transaction_id} was already in the DB. Skipping."
      return true
    end
    
    
    donation = Donation.new(
      :paypal_transaction_id => notify.transaction_id,
      :amount => notify.amount,
      :donated_at => donated_at,
      :currency => notify.currency,
      :email => params['payer_email'],
      :donation_method => 'paypal'
    )

    # Process non latin characters coming from Paypal in names and surnames
    begin
      first_name = params['first_name'].force_encoding('ISO-8859-1').encode('UTF-8')
      last_name = params['last_name'].force_encoding('ISO-8859-1').encode('UTF-8')
      country = params['address_country'] || params['residence_country']
    rescue
      first_name = ""
      last_name = ""
      country = ""
    end

    # Autoassign Single Donations to Single Donations category
    if params['subscr_id'].blank? && params['recurring_payment_id'].blank? && params['txn_type'] != 'recurring_payment'
      donation.category = Category.where(id: 5).first
    end

    # Add the user to sponsors list in the website, if he was not already there
    begin
      AddToSponsorsList.new(country, first_name, last_name).call
    rescue => exception
      ExceptionNotifier.notify_exception(exception, :env => request.env, :data => {:message => "Adding an Sponsor to the list failed"})
      Rails.logger.info "ERROR in AddToSponsorsList"
    end

    # Try to assign the donation to a user automatically
    if donation.save
      AssignUserAutomatically.new(donation, params['subscr_id'].present?, first_name, last_name).try_to_assign_user
    else
      logger.info "Error while creating donation: #{donation.errors.inspect}"
    end
  end
end