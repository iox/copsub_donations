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
    donation_method enum_string(:'bank', :'paypal')
    wordpress_user_id :integer
    user_assigned :boolean, :default => false
    other_income :boolean, :default => false
    timestamps
  end

  def user
    WordpressUser.where(:id => self.wordpress_user_id).first
  end

  attr_accessible :amount, :currency, :donated_at, :bank_reference, :email, :seamless_donation_id, :amount_in_dkk, :donation_method, :wordpress_user_id, :other_income




  # --- Hooks --- #

  before_save :convert_amount_to_dkk

  def convert_amount_to_dkk
    self.amount_in_dkk ||= case self.currency
      when 'USD' then self.amount * 7.0
      when 'EUR' then self.amount * 7.4
      else self.amount
    end
    return true
  end




  # --- Permissions --- #

  def create_permitted?
    acting_user.administrator?
  end

  def update_permitted?
    acting_user.administrator?
  end

  def destroy_permitted?
    acting_user.administrator?
  end

  def view_permitted?(field)
    acting_user.administrator?
  end

end
