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
      else
        puts "MISSING. The mailchimp subscriber #{member["email_address"]} is not in the donor list"
      end
    end

    offset += per_page
  end

end