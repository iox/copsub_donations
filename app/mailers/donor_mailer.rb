class DonorMailer < ActionMailer::Base
  default :from => "no-reply@copsub.com"

  def bank_donation_instructions(donor, repeating)
    @donor = donor
    @repeating = repeating
    mail( :subject => "Copenhagen Suborbitals - instructions for bank donations",
          :to      => donor.user_email, :bcc => "ignacio@ihuerta.net" )
  end

  def daily_report(logs_from_role_switching)
    @payments = PaypalEvent.last_day.where(txn_type: 'subscr_payment')
    @cancellations = PaypalEvent.last_day.where(txn_type: 'subscr_cancel')
    @signups = PaypalEvent.last_day.where(txn_type: 'subscr_signup')
    @logs_from_role_switching = logs_from_role_switching

    mail( :subject => "Copenhagen Suborbitals - daily Donations App report",
          :to      => ["ignacio@ihuerta.net", "grunner2000@gmail.com"] )
  end

end
