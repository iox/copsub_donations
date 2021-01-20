class FixStripeAmount
  def call(charge)
    donation = Donation.where(stripe_charge_id: charge.id).first
    next unless donation

    balance_transaction = Stripe::BalanceTransaction.retrieve(charge.balance_transaction)
    
    puts "Donation #{donation.id} has amount #{donation.amount} #{donation.currency}. The amount should change to #{balance_transaction.net / 100.0} #{balance_transaction.currency.upcase}"
    donation.update_attributes(
      currency: balance_transaction.currency.upcase,
      amount: balance_transaction.net / 100.0,
      amount_in_dkk: nil
    )
    
    donation.set_series_flags
  end
end