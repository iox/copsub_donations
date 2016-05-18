task :daily_donor_update => :environment do

  log = "Daily report for donors\n----------------\n"
  log += "\nThe following fields have been updated for all donors: donated_last_year_in_dkk, donated_total, first_donated_at, last_donated_at, donation_method."
  log += "\n\nAdditionally, the following users have had their roles changes automatically:"

  Donor.find_each do |donor|
    result = donor.update_amount_donated_last_year!
    if !result.blank?
      log += result
    end
  end

  log += "\n\n\n USD Exchange Rate: #{ExchangeRate.get('USD')}"
  log += "\n EUR Exchange Rate: #{ExchangeRate.get('EUR')}"

  log += "\n\n\n That's all. Have a nice day!"

  DonorMailer.daily_report(log).deliver
end