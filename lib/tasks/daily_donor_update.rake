task :daily_donor_update => :environment do

  @logs_from_role_switching = []
  Donor.find_each do |donor|
    result = donor.update_amount_donated_last_year!
    if !result.blank?
      @logs_from_role_switching << result
    end
  end
  
  for donation in Donation.where("created_at > ?", 2.days.ago)
    # Update the "last_donation_in_series" flag for donations made by donors who donated in the last couple of days
    if donation.donor
      donation.donor.donations.where("donated_at > ?", 13.months.ago).to_a.each(&:set_series_flags)
    end
  end

  DonorMailer.daily_report(@logs_from_role_switching).deliver
end