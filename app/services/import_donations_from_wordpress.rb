class ImportDonationsFromWordpress

  def initialize
    @wordpress_donations = SeamlessDonation.where("id > #{last_imported_donation_id}")
    @result = {
      :source => 'Wordpress Seamless Donations Plugin',
      :no_user_found => [],
      :user_assigned => [],
      :multiple_users_found => [],
      :already_existing => []
    }
  end

  def import
    @wordpress_donations.find_each(batch_size: 100) do |wordpress_donation|
      donation = prepare_new_donation(wordpress_donation)

      if donation.save
        status = AssignUserAutomatically.new(donation).try_to_assign_user
        @result[status] << donation
      else
        logger.info donation.errors.inspect
      end
    end

    return @result
  end

  private

  def last_imported_donation_id
    last = Donation.where("seamless_donation_id IS NOT NULL").order(:seamless_donation_id).last
    last ? last.seamless_donation_id : 0
  end

  def prepare_new_donation(wordpress_donation)
    Donation.new(
      :seamless_donation_id => wordpress_donation.id,
      :amount => wordpress_donation.amount,
      :donated_at => wordpress_donation.post_date,
      :currency => wordpress_donation.currency,
      :email => wordpress_donation.email,
      :donation_method => 'paypal'
    )
  end

end