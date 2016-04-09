class DonorMailer < ActionMailer::Base
  default :from => "no-reply@copsub.com"

  def bank_donation_instructions(donor, repeating)
    @donor = donor
    @repeating = repeating
    mail( :subject => "Copenhagen Suborbitals - instructions for bank donations",
          :to      => donor.user_email, :bcc => "ignacio@ihuerta.net" )
  end

end
