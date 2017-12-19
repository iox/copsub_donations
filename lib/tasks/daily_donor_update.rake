task :daily_donor_update => :environment do

  @logs_from_role_switching = []
  Donor.find_each do |donor|
    # Update the "last_donation_in_series" flag for donations from last year
    donor.donations.where(last_donation_in_series: true).where("donated_at > ?", 1.year.ago).to_a.each(&:set_series_flags)

    result = donor.update_amount_donated_last_year!
    if !result.blank?
      @logs_from_role_switching << result
    end
  end

  DonorMailer.daily_report(@logs_from_role_switching).deliver
end