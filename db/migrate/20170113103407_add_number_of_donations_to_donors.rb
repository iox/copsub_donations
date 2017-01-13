class AddNumberOfDonationsToDonors < ActiveRecord::Migration
  def change
    add_column :donors, :number_of_donations, :integer
  end
end
