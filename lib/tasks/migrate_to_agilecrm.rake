# encoding: utf-8

namespace :agilecrm do
  desc "Migrates users from Wordpress to AgileCRM"
  task :migrate, [:input, :output] => [:environment] do |t, args|
    # The following line runs in batches of 100 records
    threads = []
    WordpressUser.with_all_fields.find_each do |user|
      # Rename some attributes
      attributes = user.attributes
      attributes['address'] = attributes.delete('user_adress')

      # Connect to AgileCRM API
      contact = find_or_create_contact(user.user_email)
      contact.update user.attributes

      # Store the AgileCRM contact ID in the donations table
      user.donations.update_all(agilecrm_id: contact.id)

      puts "User migrated: #{user.user_email}"
    end

  end
end


def find_or_create_contact(email)
  AgileCRMWrapper::Contact.search_by_email(email) || AgileCRMWrapper::Contact.create(email: email)
end
