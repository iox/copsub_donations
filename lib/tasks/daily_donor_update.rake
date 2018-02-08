task :daily_donor_update => :environment do

  @logs_from_role_switching = []
  Donor.find_each do |donor|
    result = donor.update_amount_donated_last_year!
    if !result.blank?
      @logs_from_role_switching << result
    end
  end
  
  donors_that_need_updating = Donation.where("updated_at > ?", 2.days.ago).map(&:donor).uniq.compact
  for donor in donors_that_need_updating
    # Update the "last_donation_in_series" and "first_donation_in_series" flags for the last 4 donations of donors who have had activity recently
    donor.donations.last(4).to_a.each(&:set_series_flags)
  end

  DonorMailer.daily_report(@logs_from_role_switching).deliver
end