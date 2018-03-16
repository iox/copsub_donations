# describe DailyDonorUpdate do
#   it "handles users who donate twice a month" do
#     john = Donor.new
#     config = [
#       {date: "02.01.2018", amount: 150, should_be_marked_as_first: true, should_be_marked_as_last: false},
#       {date: "02.02.2018", amount: 150, should_be_marked_as_first: false, should_be_marked_as_last: true},
#       {date: "15.01.2018", amount: 200, should_be_marked_as_first: true, should_be_marked_as_last: false},
#       {date: "15.02.2018", amount: 200, should_be_marked_as_first: false, should_be_marked_as_last: true},
#     ]
    
#     donations = config.map do |options|
#       Donation.create(date: options[:date], amount: options[:amount], donor: john, first_donation_in_series: true, last_donation_in_series: true)
#     end
    
#     DailyDonorUpdate.new(john).run
    
#     donations.each(&:reload)
    
#     donations.each_with_index do |donation, index|
#       expect(donation.first_donation_in_series).to eq config[index].should_be_marked_as_first
#       expect(donation.last_donation_in_series).to eq config[index].should_be_marked_as_last
#     end
#   end
# end