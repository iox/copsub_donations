class UnassignUser
  # This service is used when the admin assigns a donation to a user manually

  def initialize(donation)
    @donation = donation
  end

  def unassign
    for donation in related_assigned_donations
      donation.update_attribute(:donor_id, nil)
      donation.update_attribute(:user_assigned, false)
    end
    @donation.update_attribute(:donor_id, nil)
    @donation.update_attribute(:user_assigned, false)
  end

  # This method returns a list of assigned donations which are similar to this one (made by the same user via Paypal or via Bank)
  def related_assigned_donations
    scope = Donation.where("id != ?", @donation.id).where(:donor_id => @donation.donor_id)
    if !@donation.bank_reference.blank?
      scope.where(:bank_reference => @donation.bank_reference)
    elsif !@donation.email.blank?
      scope.where(:email => @donation.email)
    else
      []
    end
  end

end