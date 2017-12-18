task :sync_paypal_transactions => :environment do
  include PayPal::SDK::REST
  
  next_id = nil
  20.times do
    payment_history = Payment.all( :count => 20, start_id: next_id )
    next_id = payment_history.next_id
    
    payment_history.payments.each_with_index do |payment, index|
      payer_info = payment.payer.payer_info
      transaction = payment.transactions.first
      sale = transaction.related_resources.first.sale
  
      

      
      
      
      if payment.state != 'approved'
        raise "The state of the payment #{payment.inspect} is not 'approved'. It is instead #{payment.state}"
      end
      
      if Donation.where(paypal_transaction_id: sale.id).count > 0
        puts "The Paypal transaction #{sale.id} was already in the DB. Skipping."
        next
      end
      
      
      puts "Paypal transaction ID #{sale.id} not found in our DB. Saving new donation."
      puts "State: #{payment.state}"
      puts "Payer Email: #{payer_info.email}"
      puts "Payer First Name: #{payer_info.first_name}"
      puts "Payer Last Name: #{payer_info.last_name}"
      puts "Amount: #{transaction.amount.total} #{transaction.amount.currency}"
      puts "Billing agreement: #{sale.billing_agreement_id}"
      puts "Create time: #{I18n.l(payment.create_time.to_date)}"
      puts "\n\n\n\n\n"
      
      
      donation = Donation.new(
        :paypal_transaction_id => sale.id,
        :amount => transaction.amount.total,
        :donated_at => payment.create_time,
        :currency => transaction.amount.currency,
        :email => payer_info.email,
        :donation_method => 'paypal'
      )
      
      # Autoassign Single Donations to Single Donations category
      if sale.billing_agreement_id.blank?
        donation.category = Category.where(id: 5).first
      end
      
      
      # Try to assign the donation to a user automatically
      if donation.save
        AssignUserAutomatically.new(donation,sale.billing_agreement_id.present?, payer_info.first_name, payer_info.last_name).try_to_assign_user
      else
        raise "Error - donation could not be saved: #{donation.inspect}"
      end
    end
  end

end