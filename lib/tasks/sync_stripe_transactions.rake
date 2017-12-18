task :sync_stripe_transactions => :environment do
  list = Stripe::Charge.list
  for charge in list.data
    if charge.status != 'succeeded'
      puts "Skipping. charge.status #{charge.status}"
      next
    end
    
    if Donation.where(stripe_charge_id: charge.id).count > 0
      puts "This Stripe charge is already in the DB. Skipping"
      next
    end
    

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
    
    
    
    donation = Donation.new(
      stripe_charge_id: charge.id,
      amount: charge.amount / 100,
      currency: charge.currency.upcase,
      email: email,
      donated_at: DateTime.strptime(charge.created.to_s,'%s'),
      donation_method: 'stripe',
      notes: charge.source.to_s
    )
    
    if charge.source.customer.blank?
      donation.category = Category.where(id: 5).first
    end
    
    
    # Try to assign the donation to a user automatically
    if donation.save!
      AssignUserAutomatically.new(donation, charge.source.customer.present?, first_name, last_name).try_to_assign_user
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