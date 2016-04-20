task :sync_mailchimp_status => :environment do

  Donor.update_all("mailchimp_status = 'not_present'")

  gibbon = Gibbon::Request.new

  list_info = gibbon.lists(MAILCHIMP_LIST_ID).retrieve


  member_count = list_info["stats"]["member_count"]
  offset = 0
  per_page = 100

  while (offset < member_count)
    result = gibbon.lists(MAILCHIMP_LIST_ID).members.retrieve(params: {count: per_page, offset: offset})
    for member in result["members"]
      donor = Donor.where(user_email: member["email_address"]).first
      if donor && member["status"] == 'subscribed'
        puts "OK. The mailchimp subscriber #{member["email_address"]} is in the donor list (id #{donor.id})"
        donor.update_attribute(:mailchimp_status, "subscribed")
      elsif donor
        puts "OK BUT UNSUBSCRIBED. The mailchimp unsubscribed member #{member["email_address"]} is in the donor list (id #{donor.id})"
        donor.update_attribute(:mailchimp_status, "unsubscribed")
      elsif member["status"] == 'subscribed'
        puts "MISSING. The mailchimp subscriber #{member["email_address"]} is not in the donor list. Creating it."
        donor = Donor.new
        donor.role = "subscriber"
        donor.user_email = member["email_address"]
        if member["merge_fields"]
          donor.display_name = "#{member["merge_fields"]["FNAME"]} #{member["merge_fields"]["LNAME"]}"
        end
        donor.mailchimp_status = "subscribed"
        donor.donated_last_year_in_dkk = 0
        donor.save

        puts "\n\n\n"
        puts donor.inspect
        puts "\n\n\n"
      else
        puts "MISSING. The mailchimp unsubscribed member #{member["email_address"]} is not in the donor list. Ignoring it."
      end
    end

    offset += per_page
  end

end