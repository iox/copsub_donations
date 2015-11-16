class PaypalController < ApplicationController

  skip_before_filter :authenticate
  protect_from_forgery :except => [:ipn]

  include OffsitePayments::Integrations
  require 'money'
  # OffsitePayments.mode = :test

  def ipn
    log = "Paypal IPN received. params:\n"
    log += params.inspect.to_s

    notify = Paypal::Notification.new(request.raw_post)
    log += notify.inspect.to_s

    if notify.acknowledge
      notify.complete? ? store_donation(notify) : (log += "\nNotification is not complete, please investigate".to_s)
    else
      log += "\nFailed to verify Paypal's notification, please investigate"
    end

    logger.error log
    ActionMailer::Base.mail(from: 'no-reply@copsub.com', to: 'rasmusagdestein.e9187@m.evernote.com', subject: 'Donations app received a Paypal IPN @CopSub_Log', body: log).deliver
    head 200
  end

  private

  def store_donation(notify)
    donation = Donation.new(
      :paypal_transaction_id => notify.transaction_id,
      :amount => notify.amount,
      :donated_at => notify.received_at,
      :currency => notify.currency,
      :email => params['payer_email'],
      :donation_method => 'paypal'
    )

    # Autoassign Single Donations to Single Donations category
    if params['subscr_id'].blank?
      donation.category = Category.where(id: 5).first
    end

    # Add the user to sponsors list in the website, if he was not already there
    begin
      AddToSponsorsList.new(params['address_country'], params['first_name'], params['last_name']).call
    rescue => exception
      ExceptionNotifier.notify_exception(exception, :env => request.env, :data => {:message => "Adding an Sponsor to the list failed"})
      Rails.logger.info "ERROR in AddToSponsorsList"
    end

    if donation.save
      AssignUserAutomatically.new(donation).try_to_assign_user
    else
      logger.info "Error while creating donation: #{donation.errors.inspect}"
    end
  end
end