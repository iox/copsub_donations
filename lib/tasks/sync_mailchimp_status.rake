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
      donor = Donor.where("user_email = ? OR paypalid = ?", member["email_address"], member["email_address"]).first

      # A. Mailchimp subscriber known in our donations app
      if donor && member["status"] == 'subscribed'
        puts "OK. The mailchimp subscriber #{member["email_address"]} is in the donor list (id #{donor.id})"
        donor.update_attribute(:mailchimp_status, "subscribed")
        donor.update_attribute(:role, 'subscriber') if donor.role == 'inactive_subscriber'

      elsif donor
        puts "OK BUT UNSUBSCRIBED. The mailchimp unsubscribed member #{member["email_address"]} is in the donor list (id #{donor.id})"
        donor.update_attribute(:mailchimp_status, "unsubscribed")
        donor.update_attribute(:role, 'inactive_subscriber') if donor.role == 'subscriber'


      # B. Mailchimp subscriber known in our donations app
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

      else
        puts "MISSING. The mailchimp unsubscribed member #{member["email_address"]} is not in the donor list. Ignoring it."
      end


      # Sync role back to mailchimp
      if donor && member['merge_fields']['MMERGE5'] != donor.role
        puts "Switching #{member['email_address']}'s role from #{member['merge_fields']['MMERGE5']} to #{donor.role}"
        gibbon.lists(MAILCHIMP_LIST_ID).members(member["id"]).update(body: { merge_fields: {:"MMERGE5" => donor.role} })
      end
    end

    offset += per_page
  end

end