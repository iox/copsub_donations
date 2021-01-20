
class PaypalSyncService

  def initialize
  end

  def get_token(auth)
    HTTParty.post(
      "https://api.paypal.com/v1/oauth2/token", 
      basic_auth: auth,
      headers: { 'Accept' => 'application/json' },
      body: "grant_type=client_credentials"
    ).parsed_response["access_token"]
  end

  def sync_paypal_transactions(auth)
    token = get_token(auth)
    
    queryAnswer = HTTParty.get(
      'https://api.paypal.com/v1/reporting/transactions',
      query: {
        start_date: (Time.now-1.month).to_datetime.rfc3339,
        end_date: Time.now.to_datetime.rfc3339, #"2018-06-25T14:07:46+02:00",
        fields: "all",
        page_size: 500
      },
      # 'https://api.paypal.com/v1/payments/payment?count=10',
      headers: {
        "Content-Type" => "application/json",
        "Authorization" => "Bearer #{token}"
      }
    )


    queryAnswer.parsed_response["transaction_details"].each do |transaction|
      payer_info = transaction["payer_info"]
      transaction_info = transaction["transaction_info"]
      
      
      
      if Donation.where(paypal_transaction_id: transaction_info["transaction_id"]).count > 0
        puts ">>>>>> The Paypal transaction #{transaction_info["transaction_id"]} was already in the DB. Skipping."
        next
      end
      
      if transaction_info["transaction_event_code"] == 'T0002'
        recurring = true
      elsif transaction_info["transaction_event_code"] == 'T0006'
        puts ">>>>>> one time donation!"
        recurring = false
      else
        # Ignore other transactions, for example when we take money out of the Paypal account
        puts ">>>>>> Ignoring transaction #{transaction_info["transaction_id"]}, because the transaction_event_code is #{transaction_info["transaction_event_code"]}"
        next
      end
      
      amount = transaction_info["transaction_amount"]["value"].to_f + transaction_info["fee_amount"]["value"].to_f
      
      puts "Paypal transaction ID #{transaction_info["transaction_id"]} not found in our DB. Saving new #{recurring ? 'recurring' : 'single' } donation."
      puts "Payer Email: #{payer_info["email_address"]}"
      puts "Payer First Name: #{payer_info["payer_name"]["given_name"]}"
      puts "Payer Last Name: #{payer_info["payer_name"]["surname"]}"
      puts "Amount: #{amount} #{transaction_info["transaction_amount"]["currency_code"]}"
      puts "Create time: #{I18n.l(transaction_info["transaction_initiation_date"].to_date)}"
      puts "\n\n\n\n\n"
      
      
      donation = Donation.new(
        :paypal_transaction_id => transaction_info["transaction_id"],
        :amount => amount,
        :donated_at => transaction_info["transaction_initiation_date"].to_time,
        :currency => transaction_info["transaction_amount"]["currency_code"],
        :email => payer_info["email_address"],
        :donation_method => 'paypal'
      )
      
      # Autoassign Single Donations to Single Donations category
      if recurring == false
        donation.category = Category.where(id: 5).first
      end
      
      
      # Try to assign the donation to a user automatically
      if donation.save
        AssignUserAutomatically.new(donation, recurring, payer_info["payer_name"]["given_name"], payer_info["payer_name"]["surname"]).try_to_assign_user
      else
        raise "Error - donation could not be saved: #{donation.inspect}"
      end
    end
  end




  def fix_paypal_amounts_with_fee(auth)
    token = get_token(auth)
    
    for number in (1..12).to_a
      start_month = number
      end_month = number - 1
      queryAnswer = HTTParty.get(
        'https://api.paypal.com/v1/reporting/transactions',
        query: {
          start_date: (Time.now-start_month.months).to_datetime.rfc3339,
          end_date: (Time.now-end_month.months).to_datetime.rfc3339, #"2018-06-25T14:07:46+02:00",
          fields: "all",
          page_size: 500
        },
        # 'https://api.paypal.com/v1/payments/payment?count=10',
        headers: {
          "Content-Type" => "application/json",
          "Authorization" => "Bearer #{token}"
        }
      )
    
    
      queryAnswer.parsed_response["transaction_details"].each_with_index do |transaction, index|
        transaction_info = transaction["transaction_info"]
        
        donation = Donation.where(paypal_transaction_id: transaction_info["transaction_id"]).first
        
        next unless donation
        next unless ['T0002', 'T0006'].include? transaction_info["transaction_event_code"]

        amount = transaction_info["transaction_amount"]["value"].to_f + transaction_info["fee_amount"]["value"].to_f
        puts "Donation #{donation.id} has amount #{donation.amount} #{donation.currency}. The amount should change to #{amount} #{transaction_info["transaction_amount"]["currency_code"]}"
        donation.update_attributes(amount: amount, amount_in_dkk: nil)
      end
    end
  end
end