class AssignUserAutomatically
  # This service tries to find a user to a new donation

  def initialize(donation)
    @donation = donation
  end

  # This methods returns :user_assigned, :no_user_found or :multiple_users_found
  def try_to_assign_user
    # Step 1: Try to see if there was a previous donation from the same email/bank reference
    if @donation.wordpress_user_id.blank?
      donation = search_for_similar_assigned_donation
      @donation.wordpress_user_id = donation.wordpress_user_id if donation
    end

    # Step 2: If that didn't work and we have a bank reference, check if there's a user with a paymentid field that matches
    if @donation.wordpress_user_id.blank? && !@donation.bank_reference.blank?
      # Step 2.1: Divide the bank reference into words and search for them independently. For example "12345 John Smith" >> ['12345', 'John', 'Smith']
      search_string = @donation.bank_reference.split(" ").map{|string| "paymentid.meta_value LIKE '%#{Mysql2::Client.escape(string)}%'"}.join(" OR ")
      users = WordpressUser.with_all_fields.where(search_string)
      # Step 2.2: Only accept as valid those users whose complete bank reference matches. For example, accept "John Smith" or "12345 John". But not "John Johansen".
      users.select!{|u| @donation.bank_reference.include?(u.paymentid)}
      if users.size == 1
        @donation.wordpress_user_id = users.first.id
      elsif users.size > 1
        return :multiple_users_found
      end
    end

    # Step 3: store a boolean value to facilitate searching
    if @donation.wordpress_user_id.blank?
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
    scope = Donation.where("wordpress_user_id IS NOT NULL")
    if !@donation.bank_reference.blank?
      scope.where(:bank_reference => @donation.bank_reference).first
    elsif !@donation.email.blank?
      scope.where(:email => @donation.email).first
    else
      nil
    end
  end

end