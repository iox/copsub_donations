task :sync_stripe_transactions => :environment do

  Stripe.api_key = ENV['STRIPE_CS_API_KEY']
  list = Stripe::Charge.list
  list.auto_paging_each do | charge |
    ProcessStripeCharge.new.call(charge)
  end
  
  Stripe.api_key = ENV['STRIPE_CSS_API_KEY']
  list = Stripe::Charge.list
  list.auto_paging_each do | charge |
    ProcessStripeCharge.new.call(charge)
  end
end





task :fix_stripe_amounts => :environment do
  Stripe.api_key = ENV['STRIPE_CS_API_KEY']
  list = Stripe::Charge.list
  list.auto_paging_each do | charge |
    FixStripeAmount.new.call(charge)
  end

  Stripe.api_key = ENV['STRIPE_CSS_API_KEY']
  list = Stripe::Charge.list
  list.auto_paging_each do | charge |
    FixStripeAmount.new.call(charge)
  end
end