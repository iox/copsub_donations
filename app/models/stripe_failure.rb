class StripeFailure < ActiveRecord::Base

  hobo_model # Don't put anything above this

  fields do
    amount         :decimal, :required, :precision => 8, :scale => 2
    amount_in_dkk  :decimal, :precision => 8, :scale => 2
    currency       enum_string(:'DKK', :'EUR', :'USD')
    failed_at     :datetime
    email          :string
    stripe_charge_id :string
    error_message           :text
    timestamps
  end
  attr_accessible :amount, :amount_in_dkk, :currency, :failed_at, :email, :stripe_charge_id, :error_message

  belongs_to :donor

  before_save :convert_amount_to_dkk
  
  def convert_amount_to_dkk
    self.amount_in_dkk ||= self.amount * ExchangeRate.get(self.currency)
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
    true
  end

end
