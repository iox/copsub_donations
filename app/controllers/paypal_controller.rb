class PaypalController < ApplicationController



  skip_before_filter :authenticate
  protect_from_forgery :except => [:ipn]
  before_filter :override_cors_limitations


    # require 'paypal-sdk-rest'
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
    
    PayPal::SDK::REST.set_config(
      :mode => "sandbox", # "sandbox" or "live"
      :client_id => "AdvlojC9PCoHlc57G9CRXdqrLkDTyOMuahwm5pWhLBLYXF3YybigM1E1vFAfOYYesmNrS-QDLdTAMcRK",
      :client_secret => "ELixA3D_qAmB97EaiMnxt7-TQZwmMxL57SwERllGCfgmLoxPdV3z5AK7VTDFt17m2-p65YIY4d3AL4Pu")
    
    plan = Plan.new({
      "name" => "T-Shirt of the Month Club Plan",
      "description" => "Template creation.",
      "type" => "fixed",
      "payment_definitions" => [
          {
              "name" => "Regular Payments",
              "type" => "REGULAR",
              "frequency" => "MONTH",
              "frequency_interval" => "2",
              "amount" => {
                  "value" => "100",
                  "currency" => "USD"
              },
              "cycles" => "12",
              "charge_models" => [
                  {
                      "type" => "SHIPPING",
                      "amount" => {
                          "value" => "10",
                          "currency" => "USD"
                      }
                  },
                  {
                      "type" => "TAX",
                      "amount" => {
                          "value" => "12",
                          "currency" => "USD"
                      }
                  }
              ]
          }
      ],
      "merchant_preferences" => {
          "setup_fee" => {
              "value" => "1",
              "currency" => "USD"
          },
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
      "name" => "T-Shirt of the Month Club Plan",
      "description" => "Template creation.",
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
  
  
  
  
  
  
  
  
  
  
  
  

  private

  def store_paypal_event(notify)
    clean_params = params.inject({}) { |h, (k, v)| h[k] = v.force_encoding('ISO-8859-1').encode('UTF-8'); h }
    PaypalEvent.create(clean_params)
  end

  def store_donation(notify)
    donation = Donation.new(
      :paypal_transaction_id => notify.transaction_id,
      :amount => notify.amount,
      :donated_at => notify.received_at,
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
    if params['subscr_id'].blank?
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