class Donation < ActiveRecord::Base

  hobo_model # Don't put anything above this

  fields do
    amount         :decimal, :required, :precision => 8, :scale => 2
    amount_in_dkk  :decimal, :precision => 8, :scale => 2
    currency       enum_string(:'DKK', :'EUR', :'USD')
    donated_at     :datetime
    bank_reference :string
    email          :string
    seamless_donation_id :integer
    donation_method enum_string(:'bank', :'paypal', :'stripe')
    wordpress_user_id :integer
    user_assigned :boolean, :default => false
    other_income :boolean, :default => false
    paypal_transaction_id :string
    stripe_charge_id :string
    notes           :text
    first_donation_in_series :boolean, :default => false
    last_donation_in_series :boolean, :default => false
    stopped_donating_date :date
    timestamps
  end

  def user
    Donor.where(:id => self.donor_id).first
  end
  
  def self.donor_assigned
    self.where(other_income: false).where("donor_id IS NOT NULL")
  end

  belongs_to :category
  belongs_to :donor

  attr_accessible :amount, :currency, :donated_at, :bank_reference, :email, :seamless_donation_id, :amount_in_dkk, :donation_method, :wordpress_user_id, :other_income, :category, :category_id, :paypal_transaction_id, :donor, :donor_id, :notes, :stripe_charge_id

  # --- Hooks --- #

  before_save :convert_amount_to_dkk, :set_default_category
  after_create :set_series_flags
  after_save :cache_amount_donated_last_year

  def convert_amount_to_dkk
    self.amount_in_dkk ||= self.amount * ExchangeRate.get(self.currency)
    return true
  end

  def cache_amount_donated_last_year
    if user
      user.update_amount_donated_last_year!
    end
  end

  def set_default_category
    self.category ||= Category.where(default: true).first
  end
  
  def set_series_flags
    first_donation_in_series = false
    last_donation_in_series = false
    stopped_donating_date = nil

    # Only do further checks if the category is not Single Donations, and a donor has been set for this donation
    if self.category_id != 5 && self.donor.present?
      # When setting first_donation_in_series, we take into account donors who have taken a long pause, by checking whether they have donated in the last X days. With X days being twice their regular interval.
      reasonable_date_range_past = self.donated_at - (donor.donation_interval*2).days
      if donor.donations.where("id != ?", self.id).where("amount > ? AND amount < ?", (self.amount * 0.8), (self.amount * 1.2)).where("donated_at < ?", self.donated_at).where("donated_at > ?", reasonable_date_range_past).count == 0
        first_donation_in_series = true
      end
    
      reasonable_date_range_future = self.donated_at + (donor.donation_interval*2).days
      if donor.donations.where("id != ?", self.id).where("amount > ? AND amount < ?", (self.amount * 0.8), (self.amount * 1.2)).where("donated_at > ?", self.donated_at).where("donated_at < ?", reasonable_date_range_future).count == 0
        last_donation_in_series = true
        stopped_donating_date = self.donated_at.to_date + donor.donation_interval + 5.days
      end
    end
    
    # Save attributes without invoking callbacks
    Donation.where(id: self.id).update_all(first_donation_in_series: first_donation_in_series, last_donation_in_series: last_donation_in_series, stopped_donating_date: stopped_donating_date)
  end

  def default_search_value
    return email if email

    only_numbers_bank_reference = bank_reference ? bank_reference.gsub(/[^0-9]/, '') : ""
    if only_numbers_bank_reference.size > 2
      only_numbers_bank_reference
    else
      bank_reference ? bank_reference.split.join(" ") : "" # Remove extra spaces
    end
  end

  # --- Permissions --- #

  def create_permitted?
    acting_user.administrator?
  end

  def update_permitted?
    acting_user.administrator?
  end

  def destroy_permitted?
    false
  end

  def view_permitted?(field)
    acting_user
  end

end
