class DonorMailer < ActionMailer::Base
  default :from => "no-reply@copsub.com"

  def bank_donation_instructions(donor, repeating)
    subject = "Copenhagen Suborbitals - instructions for bank donations"
    EmailLog.create(email: donor.user_email, subject: subject)
    @donor = donor
    @repeating = repeating
    mail( :subject => subject,
          :to      => donor.user_email, :bcc => ["ignacio@ihuerta.net", "grunner2000@gmail.com", "mads@madswilson.dk"] ) do |format|
      format.html { render layout: 'basic_email' }
      format.text
    end
  end
  
  def thank_you(donor, repeating)
    if repeating
      subject = "Copenhagen Suborbitals - thank you for becoming a supporter"
    else
      subject = "Copenhagen Suborbitals - thank you for your donation"
    end
    EmailLog.create(email: donor.user_email, subject: subject)
    @donor = donor
    @repeating = repeating
    mail( :subject => subject,
          :to      => donor.user_email, :bcc => ["ignacio@ihuerta.net", "grunner2000@gmail.com", "mads@madswilson.dk"] ) do |format|
      format.html { render layout: 'basic_email' }
      format.text
    end
  end

  def daily_report(logs_from_role_switching)
    @paypal_events = PaypalEvent.last_day.group(:txn_type).count
    @logs_from_role_switching = logs_from_role_switching

    mail( :subject => "Copenhagen Suborbitals - daily Donations App report",
          :to      => ["ignacio@ihuerta.net", "grunner2000@gmail.com"] )
  end

end
