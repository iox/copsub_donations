task :clone_wordpress_users => :environment do
  # Donor.delete_all

  total = WordpressUser.count
  current = 0

  WordpressUser.with_all_fields.find_each do |wpuser|

    donor = Donor.where(wordpress_id: wpuser.id).first || Donor.new
    donor.wordpress_id = wpuser.id
    donor.user_email = wpuser.user_email
    donor.user_login = wpuser.user_login
    donor.display_name = wpuser.display_name
    donor.user_adress = wpuser.user_adress
    donor.city = wpuser.city
    donor.country = wpuser.country
    donor.paymentid = wpuser.paymentid
    donor.user_phone = wpuser.user_phone
    donor.donated_last_year_in_dkk = wpuser.donated_last_year_in_dkk
    donor.role = wpuser.role

    # Note: these 2 fields have been renamed
    donor.paypalid = wpuser.paypal_id
    donor.alternativeid = wpuser.alternative_id


    donor.save

    Donation.where(wordpress_user_id: wpuser.id).update_all(donor_id: donor.id)

    current += 1

    puts "#{current}/#{total}"
  end

end