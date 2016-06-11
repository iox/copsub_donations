task :daily_donor_update => :environment do

  @logs_from_role_switching = []
  Donor.find_each do |donor|
    result = donor.update_amount_donated_last_year!
    if !result.blank?
      @logs_from_role_switching << result
    end
  end

  DonorMailer.daily_report(@logs_from_role_switching).deliver
end