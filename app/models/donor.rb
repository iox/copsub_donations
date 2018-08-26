class Donor < ActiveRecord::Base

  hobo_model # Don't put anything above this

  fields do
    wordpress_id             :integer
    user_email               :string
    first_name               :string
    last_name                :string
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
    donation_method enum_string(:'bank', :'paypal', :'stripe')
    last_paypal_failure      :date
    last_paypal_failure_type :string
    notes                    :text
    number_of_donations      :integer, default: 0
    selected_donor_type      :string
    selected_amount          :integer
    stripe_customer_id       :string
    stripe_card_expiration_date :date
    stopped_regular_donations_date :date
    filled_donation_form_date :date
    custom_donation_interval :integer
    force_display_as_sponsor :boolean, default: false
    timestamps
  end
  attr_accessible :wordpress_id, :user_email, :first_name, :last_name, :user_adress, :city, :country, :paymentid, :paypalid, :alternativeid, :user_phone, :role, :old_notes_backup, :stopped_regular_donations_date, :filled_donation_form_date, :custom_donation_interval, :force_display_as_sponsor

  has_many :donations
  has_many :role_changes
  has_many :notes
  
  children :notes

  ROLES = [:single_supporter, :subscriber, :inactive_supporter, :recurring_supporter, :inactive_subscriber]

  USER_FIELDS = %w{id user_email first_name last_name}
  USERMETA_FIELDS = %w{user_adress city country paymentid paypalid user_phone donated_last_year_in_dkk alternativeid}

  ALL_FIELDS = USER_FIELDS + USERMETA_FIELDS + ['role']


  def role=(val)
    # Store the previous role temporarily when assigned to new value
    @previous_role = self.role unless val == self.role
    write_attribute(:role, val)
  end

  after_save :record_role_changes
  def record_role_changes
    if @previous_role
      RoleChange.create(donor: self, previous_role: @previous_role, new_role: self.role)
      @previous_role = nil
    end
  end

  after_create :store_first_role_change
  def store_first_role_change
    RoleChange.create(donor: self, previous_role: '-', new_role: self.role)
  end


  def paypal_events
    last_paypal_email = self.donations.last.try(:email)
    if last_paypal_email
      PaypalEvent.where("txn_type != 'subscr_payment'").where("payer_email = ?", last_paypal_email)
    else
      return []
    end
  end

  def last_paypal_failure_code
    case last_paypal_failure_type
    when 'recurring_payment_suspended_due_to_max_failed_payment'
      1
    when 'subscr_eot'
      2
    when 'subscr_failed'
      3
    when 'subscr_cancel'
      4
    else
      0
    end
  end
  
  
  def self.find_by_any_email(email)
    email = email.strip
    where("user_email LIKE ? OR paypalid LIKE ? OR paymentid LIKE ? OR alternativeid LIKE ?", email, email, email, email)
  end


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
    log = ""

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

    # Autoassign single_supporter role
    #---------------------------------
    if self.role == 'subscriber' && last_donation && last_donation.donated_at > 1.month.ago
      log += "\n- Donor #{self.id}-#{self.user_email} has switched roles from #{self.role} to single_supporter, because he has donated during the last month."
      self.role = 'single_supporter'
    end

    # Autoassign recurring_supporter role
    # -----------------------------------
    # Paypal donors, whose category id is not single donations
    if self.donation_method == 'paypal' && last_donation && last_donation.category_id != 5 && self.role != 'recurring_supporter' && last_donation.donated_at > 1.month.ago
      log += "\n- Donor #{self.id}-#{self.user_email} has switched roles from #{self.role} to recurring_supporter, because his last paypal donation was not a Single Donation."
      self.role = 'recurring_supporter'
    end

    # Bank donors, who have donated more than once in the last 6 months, with the same amount
    if self.donation_method == 'bank' && last_donation
      previous_two_donations = self.donations.where("id != ?", last_donation.id).order(:donated_at).last(2)

      if previous_two_donations.size == 2 && previous_two_donations.all?{|d| d.donated_at > 6.months.ago} && self.role != 'recurring_supporter'
        log += "\n- Donor #{self.id}-#{self.user_email} has switched roles from #{self.role} to recurring_supporter, because he has donated 3 times in the last 6 months."
        self.role = 'recurring_supporter'
      end
    end

    # Count the number of donations
    self.number_of_donations = donations.count
    
    
    # Update stopped_regular_donations_date
    # Only applies to donors who have been a recurring supporter at some point, and who have not donated in the last month
    if self.donations.count > 3 && last_donation.donated_at < (donation_interval+5).days.ago && (self.donations.count - self.donations.map(&:amount).uniq.size) > 2
      # We estimate that the "stopped_regular_donations_date" is the last donation date + 35 days. That is when we realised that this donor is not donating any more
      self.stopped_regular_donations_date = last_donation.donated_at.to_date + 1.month
    else
      self.stopped_regular_donations_date = nil
    end

    self.save
    
    return log
  end
  
  # This methods returns the "most typical amount" a user donates
  def most_typical_amount
    amounts = donations.map(&:amount)
    freq = amounts.inject(Hash.new(0)) { |h,v| h[v] += 1; h }
    amounts.sort_by { |v| freq[v] }.last
  end
  
  def most_typical_amount_in_dkk
    most_typical_amount * ExchangeRate.get(donations.where(amount: most_typical_amount).last.currency)
  end
  
  # Most donors donate monthly, but some donate every 3 or 6 months. This method estimates this interval
  def donation_interval
    # Some donors can have a custom donation interval
    if custom_donation_interval.present?
      return custom_donation_interval
    end
    
    if donations.where(amount: most_typical_amount).count > 2
      span_secs = donations.maximum(:donated_at) - donations.minimum(:donated_at)
      avg_secs = span_secs / (donations.where(amount: most_typical_amount).count - 1)
      (avg_secs / (24 * 60 * 60)).round
    else
      30
    end
  end


  def create_stripe_customer
    if self.stripe_customer_id.blank?
      customer = Stripe::Customer.create(:email => self.user_email)
      self.update_attribute(:stripe_customer_id, customer.id)
    end
  end
  
  
  def subscribe_to_mailchimp_list
    begin
      gibbon = Gibbon::Request.new
      gibbon.lists(MAILCHIMP_LIST_ID).members.create(body: {email_address: self.user_email, status: "subscribed", merge_fields: {:"FNAME" => self.first_name || "", :"LNAME" => self.last_name || ""}})
    rescue
      Rails.logger.info "The donor could not be subscribed. He is probably on the list already."
    end
  end
  
  def full_name
    if first_name.present? || last_name.present?
      "#{first_name} #{last_name}"
    elsif user_email.present?
      user_email
    else
      "Donor #{id}"
    end
  end
  
  def notes_as_text
    notes.map{|n| I18n.l(n.created_at.to_date) + ': ' + n.body}.join('&#10;')
  end
  
  def almost_donated_mailto_template
    subject = URI.encode "Donation to Copenhagen Suborbitals"
    body = URI.encode "Hi #{first_name}, \n\nI can see that you signed up as a Copenhagen Suborbitals Supporter on #{I18n.l(filled_donation_form_date, format: :long) if filled_donation_form_date}, however we haven’t registered your payment yet?\n\nWe have recently implemented a new system for managing our donors so it might be a system error during the payment.\n\nDid you have any trouble while donating? Is there anything I can help you with?\n\nMads Wilson, Copenhagen Suborbitals"
    "mailto:#{user_email}?subject=#{subject}&body=#{body}"
  end
  
  def stopped_donating_english_mailto_template
    subject = URI.encode "Copenhagen Suborbitals Support donation"
    body = URI.encode "Hi #{first_name}, \n\nI can see in our bank that it looks like your regular CSS donation has not arrived this month. We have not heard from you so there was maybe an error with the transfer?\n\nBest regards\n\nMads Wilson, Copenhagen Suborbitals Support"
    "mailto:#{user_email}?subject=#{subject}&body=#{body}"
  end
  
  def stopped_donating_danish_mailto_template
    subject = URI.encode "Copenhagen Suborbitals Support kontingent"
    body = URI.encode "Hi #{first_name}, \n\nJeg kan se på vores bankudskrift at det ser ud som om dit CSS kontingent ikke er dukket op på kontoen i denne måned. Vi har ikke hørt noget andet så jeg tænker at der måske er en fejl i overførslen?\n\nMvh\n\nMads Wilson, Copenhagen Suborbitals Support"
    "mailto:#{user_email}?subject=#{subject}&body=#{body}"
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
