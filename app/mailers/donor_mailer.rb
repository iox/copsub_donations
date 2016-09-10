class DonorMailer < ActionMailer::Base
  default :from => "no-reply@copsub.com"

  def bank_donation_instructions(donor, repeating)
    subject = "Copenhagen Suborbitals - instructions for bank donations"
    EmailLog.create(email: donor.user_email, subject: subject)
    @donor = donor
    @repeating = repeating
    mail( :subject => subject,
          :to      => donor.user_email, :bcc => "ignacio@ihuerta.net" )
  end

  def daily_report(logs_from_role_switching)
    @paypal_events = PaypalEvent.last_day.group(:txn_type).count
    @logs_from_role_switching = logs_from_role_switching

    mail( :subject => "Copenhagen Suborbitals - daily Donations App report",
          :to      => ["ignacio@ihuerta.net", "grunner2000@gmail.com"] )
  end

end
