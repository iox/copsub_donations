class SeamlessDonation < ActiveRecord::Base
  establish_connection "wordpress_database"
  self.table_name = "#{PREFIX}posts"

  default_scope where(:post_type => 'dgx-donation').where("donation_method.meta_value = 'PAYPALSTD'").
                select("distinct #{PREFIX}posts.*, currency.meta_value as currency, amount.meta_value as amount, email.meta_value as email").
                joins("LEFT JOIN #{PREFIX}postmeta currency ON #{PREFIX}posts.id = currency.post_id AND currency.meta_key = '_dgx_donate_donation_currency'").
                joins("LEFT JOIN #{PREFIX}postmeta amount ON #{PREFIX}posts.id = amount.post_id AND amount.meta_key = '_dgx_donate_amount'").
                joins("LEFT JOIN #{PREFIX}postmeta donation_method ON #{PREFIX}posts.id = donation_method.post_id AND donation_method.meta_key = '_dgx_donate_payment_processor'").
                joins("LEFT JOIN #{PREFIX}postmeta email ON #{PREFIX}posts.id = email.post_id AND email.meta_key = '_dgx_donate_donor_email'").
                group("#{PREFIX}posts.id")

end