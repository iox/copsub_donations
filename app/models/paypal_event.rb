class PaypalEvent < ActiveRecord::Base

  hobo_model # Don't put anything above this

  fields do
    txn_type :string
    subscr_id :string
    last_name :string
    address_street :string
    address_zip :string
    address_country_code :string
    address_name :string
    address_city :string
    address_state :string
    address_country :string
    txn_id :string
    payment_type :string
    payment_fee :string
    transaction_subject :string
    residence_country :string
    item_name :string
    mc_currency :string
    business :string
    verify_sign :string
    payer_status :string
    payer_email :string
    first_name :string
    receiver_email :string
    payer_id :string
    item_number :string
    charset :string
    notify_version :string
    ipn_track_id :string
    timestamps
  end
  attr_accessible :txn_type, :subscr_id, :last_name, :address_street, :address_zip, :address_country_code, :address_name, :address_city, :address_state, :address_country, :txn_id, :payment_type, :payment_fee, :transaction_subject, :residence_country, :item_name, :mc_currency, :business, :verify_sign, :payer_status, :payer_email, :first_name, :receiver_email, :payer_id, :item_number, :charset, :notify_version, :ipn_track_id

  def find_donor
    Donor.fuzzy_search(payer_email).first
  end

  def self.last_day
    self.where("created_at > ?", Time.now - 24.hours)
  end

  after_create :store_last_paypal_failure
  def store_last_paypal_failure
    if self.find_donor
      if self.txn_type.in?(['recurring_payment_suspended_due_to_max_failed_payment', 'subscr_eot', 'subscr_failed'])
        self.find_donor.update_attribute(:last_paypal_failure, self.created_at.to_date)
        self.find_donor.update_attribute(:last_paypal_failure_type, self.txn_type)
      end

      if self.txn_type.in?(['subscr_payment', 'web_accept', 'subscr_signup'])
        self.find_donor.update_attribute(:last_paypal_failure, nil)
        self.find_donor.update_attribute(:last_paypal_failure_type, nil)
      end
    end
  end

  # --- Permissions --- #

  def create_permitted?
    acting_user.administrator?
  end

  def update_permitted?
    false
  end

  def destroy_permitted?
    false
  end

  def view_permitted?(field)
    true
  end

end
