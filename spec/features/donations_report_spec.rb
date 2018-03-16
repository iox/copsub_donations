RSpec.describe 'Donations report', :type => :feature, js: false do
  it 'allows users to send email quickly to lost donors' do
    donor = Donor.create!(user_email: 'test@test.com')
    donation = Donation.create!(currency: 'DKK', stopped_donating_date: Time.now - 3.days, amount: 100, amount_in_dkk: 100, donor: donor, donated_at: 2.months.ago)
    donation.update_attribute(:last_donation_in_series, true)
    visit '/report'
    expect(page).to have_xpath "//a[contains(@href,'test@test.com')]"
  end
end