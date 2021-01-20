class ProcessStripeCharge
  def call(charge)
    if charge.status != 'succeeded'
      puts "Skipping. charge.status #{charge.status}"
      next
    end
    
    if Donation.where(stripe_charge_id: charge.id).count > 0
      puts "This Stripe charge is already in the DB. Skipping"
      next
    end
    
    if charge.source.present?
      if charge.source.customer
        customer = Stripe::Customer.retrieve(charge.source.customer)
        email = customer.email
        first_name = charge.source.name.split(" ")[0]
        last_name = charge.source.name.split(" ")[1]
      elsif charge.source.name.include?("@")
        email = charge.source.name
        first_name = nil
        last_name = nil
      else
        email = nil
        first_name = charge.source.name.split(" ")[0]
        last_name = charge.source.name.split(" ")[1]
      end
    elsif charge.billing_details.present?
      email = charge.billing_details.email
      first_name = charge.billing_details.name.split(" ")[0]
      last_name = charge.billing_details.name.split(" ")[1]
    elsif charge.customer.present?
      customer = Stripe::Customer.retrieve(charge.source.customer)
      email = customer.email
      first_name = charge.source.name.split(" ")[0]
      last_name = charge.source.name.split(" ")[1]
    else
      email = nil
      first_name = nil
      last_name = nil
    end
    
    
    balance_transaction = Stripe::BalanceTransaction.retrieve(charge.balance_transaction)
    
    
    donation = Donation.new(
      stripe_charge_id: charge.id,
      amount: balance_transaction.net / 100.0,
      currency: balance_transaction.currency.upcase,
      email: email,
      donated_at: DateTime.strptime(charge.created.to_s,'%s'),
      donation_method: 'stripe',
      notes: charge.source.to_s
    )
    
    customer_id = charge.source ? charge.source.customer : charge.customer
    if customer_id.blank?
      donation.category = Category.where(id: 5).first
    end
    
    
    # Try to assign the donation to a user automatically
    if donation.save!
      AssignUserAutomatically.new(donation, customer_id.present?, first_name, last_name).try_to_assign_user
      
      # Update the "last_donation_in_series" flag for donations made by this donor
      donation.reload
      if donation.donor
        donation.donor.donations.last(3).to_a.each(&:set_series_flags)
      end
      
    else
      raise "Error - donation could not be saved: #{donation.inspect}"
    end
    
    puts donation.inspect
    puts "email: #{email}"
    puts "first_name: #{first_name}"
    puts "last_name: #{last_name}"
    puts "\n\n\n\n\n"
  end
end