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
  attr_accessible :amount, :currency, :donated_at, :bank_reference, :email, :seamless_donation_id, :amount_in_dkk, :donation_method, :wordpress_user_id, :other_income


  before_save :store_user_assigned, :store_amount_in_dkk

  # This method returns donations which are similar
  # It is used during user assignation: all similar donations will be assigned at the same time 
  def related_unassigned_donations
    scope = Donation.where("id != ?", self.id).where(:wordpress_user_id => nil)
    if !bank_reference.blank?
      scope.where(:bank_reference => self.bank_reference)
    elsif !email.blank?
      scope.where(:email => self.email)
    else
      []
    end
  end

  # This method tries to see if a similar donation has been assigned to the user previously
  # It's a simple attempt at "learning from history", so we don't have to assign all donations manually
  def search_for_similar_assigned_donation
    scope = Donation.where("wordpress_user_id IS NOT NULL")
    if !bank_reference.blank?
      scope.where(:bank_reference => self.bank_reference).first
    elsif !email.blank?
      scope.where(:email => self.email).first
    else
      nil
    end
  end

  def assign(user)
    self.update_attribute(:wordpress_user_id, user.id)
    for donation in self.related_unassigned_donations
      donation.update_attribute(:wordpress_user_id, user.id)
    end
  end

  def store_user_assigned
    # Step 1: Try to see if we can autoselect the user
    if self.wordpress_user_id.blank?
      similar_assigned_donation = search_for_similar_assigned_donation
      self.wordpress_user_id = similar_assigned_donation.wordpress_user_id if similar_assigned_donation
    end

    # Step 2: store a boolean value to facilitate filtering
    if self.wordpress_user_id
      self.user_assigned = true
    else
      self.user_assigned = false
    end
    return true
  end



  def store_amount_in_dkk
    if self.currency == 'USD'
      self.amount_in_dkk = self.amount * 7.0
    elsif self.currency == 'EUR'
      self.amount_in_dkk = self.amount * 7.4
    else
      self.amount_in_dkk = self.amount
    end
    return true
  end

  def user
    WordpressUser.where(:id => self.wordpress_user_id).first
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
