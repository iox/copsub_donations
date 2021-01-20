task :sync_paypal_transactions => :environment do
  PaypalSyncService.new.sync_paypal_transactions(username: ENV["PAYPAL_CS_CLIENT_ID"], password: ENV["PAYPAL_CS_SECRET"])
  PaypalSyncService.new.sync_paypal_transactions(username: ENV["PAYPAL_CSS_CLIENT_ID"], password: ENV["PAYPAL_CSS_SECRET"])
end

task :fix_paypal_amounts_with_fee => :environment do
  PaypalSyncService.new.fix_paypal_amounts_with_fee(username: ENV["PAYPAL_CS_CLIENT_ID"], password: ENV["PAYPAL_CS_SECRET"])
  PaypalSyncService.new.fix_paypal_amounts_with_fee(username: ENV["PAYPAL_CSS_CLIENT_ID"], password: ENV["PAYPAL_CSS_SECRET"])
end