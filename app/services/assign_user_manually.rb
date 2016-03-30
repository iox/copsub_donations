class AssignUserManually
  # This service is used when the admin assigns a donation to a user manually

  def initialize(donation)
    @donation = donation
  end

  def assign(user)
    @donation.update_attribute(:wordpress_user_id, user.id)
    @donation.update_attribute(:user_assigned, true)
    for donation in related_unassigned_donations
      donation.update_attribute(:wordpress_user_id, user.id)
      donation.update_attribute(:user_assigned, true)

      # TODO: Temporary hack using the new donors table. To be removed after we remove the Wordpress DB connection
      donor_id = Donor.find_by_wordpress_id(user.id).try(:id)
      donation.update_attribute(:donor_id, donor_id) if donor_id
    end
  end

  # This method returns a list of unassigned donations which are similar to this one (made by the same user via Paypal or via Bank)
  def related_unassigned_donations
    scope = Donation.where("id != ?", @donation.id).where(:wordpress_user_id => nil)
    if !@donation.bank_reference.blank?
      scope.where(:bank_reference => @donation.bank_reference)
    elsif !@donation.email.blank?
      scope.where(:email => @donation.email)
    else
      []
    end
  end

end