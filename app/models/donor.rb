class Donor < ActiveRecord::Base

  hobo_model # Don't put anything above this

  fields do
    wordpress_id             :integer
    user_email               :string
    user_login               :string
    display_name             :string
    user_adress              :text
    city                     :string
    country                  :string
    paymentid                :string
    paypalid                 :string
    alternativeid            :string
    user_phone               :string
    donated_last_year_in_dkk :integer
    donated_total            :integer
    role                     :string
    first_donated_at         :date
    last_donated_at          :date
    mailchimp_status         :string, default: "not_present"
    donation_method enum_string(:'bank', :'paypal')
    notes                    :text
    timestamps
  end
  attr_accessible :wordpress_id, :user_email, :user_login, :display_name, :user_adress, :city, :country, :paymentid, :paypalid, :alternativeid, :user_phone, :role, :notes

  has_many :donations

  ROLES = [:supporter, :subscriber, :inactive_supporter, :recurring_supporter]

  USER_FIELDS = %w{id user_email user_login display_name}
  USERMETA_FIELDS = %w{user_adress city country paymentid paypalid user_phone donated_last_year_in_dkk alternativeid}

  ALL_FIELDS = USER_FIELDS + USERMETA_FIELDS + ['role']


  # This scope method allows to search for users using several fields, for example "Donor.fuzzy_search('ignacio')"
  def self.fuzzy_search(search)
    # Build a string like: "ID LIKE :search OR user_email LIKE :search ..."
    sql_user_fields = ALL_FIELDS.map{|f|"donors.#{f} LIKE :search"}.join(" OR ")

    # If the user searches for "Ignacio Hedehusene", then
    # we'll search for records that match the two words, even in different DB fields
    scope = self
    for string in search.split(" ")
      # Search in the DB, limiting the number of results
      scope = scope.where(sql_user_fields, :search => "%#{string}%")
    end

    return scope
  end

  def update_amount_donated_last_year!
    self.donated_last_year_in_dkk = donations.where("donated_at > '#{(Date.today-1.year).to_time.to_s(:db)}'").sum(:amount_in_dkk)

    # Update the absolute total too
    self.donated_total = donations.sum(:amount_in_dkk)

    # Update the first donation date
    first_donation = self.donations.order(:donated_at).first
    if first_donation && first_donation.donated_at
      self.first_donated_at = first_donation.donated_at.to_date
    end

    # Update the last donation date
    last_donation = self.donations.order(:donated_at).last
    if last_donation && last_donation.donated_at
      self.last_donated_at = last_donation.donated_at.to_date
      # Update the donation method
      self.donation_method = last_donation.donation_method
    end

    # Autoassign recurring_supporter role
    # -----------------------------------
    # Paypal donors, whose category id is not single donations
    if self.donation_method == 'paypal' && last_donation && last_donation.category_id != 5
      self.role = 'recurring_supporter'
    end

    # Bank donors, who have donated more than once in the last 6 months, with the same amount
    if self.donation_method == 'bank' && last_donation
      previous_two_donations = self.donations.where("id != ?", last_donation.id).order(:donated_at).last(2)

      if previous_two_donations.size == 2 && previous_two_donations.all?{|d| d.donated_at > 6.months.ago}
        self.role = 'recurring_supporter'
      end
    end

    self.save
  end




  # --- Permissions --- #

  def create_permitted?
    acting_user.administrator?
  end

  def update_permitted?
    acting_user.administrator?
  end

  def destroy_permitted?
    acting_user.administrator?
  end

  def view_permitted?(field)
    true
  end

end
