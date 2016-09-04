class AssignUserAutomatically
  # This service tries to find a user to a new donation

  def initialize(donation, subscriber=false, first_name=nil, last_name=nil)
    @donation = donation
    @subscriber = subscriber
    @first_name = first_name
    @last_name = last_name
  end

  # This methods returns :user_assigned, :no_user_found or :multiple_users_found
  def try_to_assign_user
    # Step 1: Try to see if there was a previous donation from the same email/bank reference
    if @donation.donor_id.blank?
      donation = search_for_similar_assigned_donation
      @donation.donor_id = donation.donor_id if donation
    end

    # Step 2: If that didn't work and we have a bank reference, check if there's a user with a paymentid field that matches
    if @donation.donor_id.blank? && !@donation.bank_reference.blank?
      # Step 2.1: Divide the bank reference into words and search for them independently. For example "12345 John Smith" >> ['12345', 'John', 'Smith']
      search_string = @donation.bank_reference.split(" ").map{|string| "paymentid LIKE '%#{Mysql2::Client.escape(string)}%'"}.join(" OR ")
      users = Donor.where(search_string)
      # Step 2.2: Only accept as valid those users whose complete bank reference matches. For example, accept "John Smith" or "12345 John". But not "John Johansen".
      users.select!{|u| @donation.bank_reference.include?(u.paymentid)}
      if users.size == 1
        @donation.donor_id = users.first.id
      elsif users.size > 1
        return :multiple_users_found
      end
    end

    # Step 3: If that didn't work and we have en email, try to find an existing user via email
    if @donation.donor_id.blank? && !@donation.email.blank?
      user = Donor.where(user_email: @donation.email).first || Donor.where(paypalid: @donation.email).first || Donor.where(alternativeid: @donation.email).first
      if user
        @donation.donor_id = user.id
      end
    end

    # Step 4: If we have not had luck yet, create a new user
    if @donation.donor_id.blank? && !@donation.email.blank?
      user = Donor.new(user_email: @donation.email, first_name: @first_name, last_name: @last_name)
      user.role = "single_supporter"
      user.save
      @donation.donor_id = user.id
    end

    # Step 5: store a boolean value to facilitate searching
    if @donation.donor_id.blank?
      @donation.user_assigned = false
      return :no_user_found
    else
      @donation.user_assigned = true
      @donation.save
      return :user_assigned
    end
  end


  private

  # This method tries to see if a similar donation has been assigned to the user previously
  # It's a simple attempt at "learning from history", so we don't have to assign all donations manually
  def search_for_similar_assigned_donation
    scope = Donation.where("donor_id IS NOT NULL")
    if !@donation.bank_reference.blank?
      scope.where(:bank_reference => @donation.bank_reference).first
    elsif !@donation.email.blank?
      scope.where(:email => @donation.email).first
    else
      nil
    end
  end

end