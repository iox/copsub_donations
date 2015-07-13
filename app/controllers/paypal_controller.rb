class PaypalController < ApplicationController

  skip_before_filter :authenticate
  protect_from_forgery :except => [:ipn]

  include OffsitePayments::Integrations
  require 'money'

  def ipn
    logger.info "Paypal IPN received. params:"
    logger.info params.inspect

    notify = Paypal::Notification.new(request.raw_post)
    logger.info notify.inspect

    if notify.acknowledge
      notify.complete? ? store_donation(notify) : logger.error("Notification is not complete, please investigate")
    else
      logger.error("Failed to verify Paypal's notification, please investigate")
    end

    head 200
  end

  private

  def store_donation(notify)
    donation = Donation.new(
      :transaction_id => notify.transaction_id,
      :amount => notify.amount,
      :donated_at => notify.received_at,
      :currency => notify.currency,
      :email => params['payer_email'],
      :donation_method => 'paypal'
    )
    if !donation.save
      logger.info "Error while creating donation: #{donation.errors.inspect}"
    end
  end
end