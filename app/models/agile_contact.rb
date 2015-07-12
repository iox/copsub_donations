class AgileContact < AgileCRMWrapper::Contact
  BASIC_FIELDS = %w{ email city country paymentid paypal_id user_phone role}
  ALL_FIELDS = BASIC_FIELDS + %w{address wordpress_id display_name donated_last_year_in_dkk}

  def method_missing(method, *arguments, &block)
    # the first argument is a Symbol, so you need to_s it if you want to pattern match
    if ALL_FIELDS.include? method.to_s
      get_property(method.to_s)
    else
      super
    end
  end

  def update_amount_donated_last_year!
    self.update(donated_last_year_in_dkk: donations.where("donated_at > '#{(Date.today-1.year).to_time.to_s(:db)}'").sum(:amount_in_dkk))
  end

  def donations
    Donation.where(:agilecrm_id => self.id)
  end
end
