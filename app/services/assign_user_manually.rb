class AssignUserManually
  # This service is used when the admin assigns a donation to a user manually

  def initialize(donation)
    @donation = donation
  end

  def assign(user)
    @donation.update_attribute(:donor_id, user.id)
    @donation.update_attribute(:user_assigned, true)
    for donation in related_unassigned_donations
      donation.update_attribute(:donor_id, user.id)
      donation.update_attribute(:user_assigned, true)
    end
  end

  # This method returns a list of unassigned donations which are similar to this one (made by the same user via Paypal or via Bank)
  def related_unassigned_donations
    scope = Donation.where("id != ?", @donation.id).where(:donor_id => nil)
    if !@donation.bank_reference.blank? && !@donation.bank_reference.to_s.mb_chars.downcase.to_s.strip.in?(BANK_REFERENCE_BLACKLIST)
      scope.where(:bank_reference => @donation.bank_reference)
    elsif !@donation.email.blank?
      scope.where(:email => @donation.email)
    else
      []
    end
  end

end