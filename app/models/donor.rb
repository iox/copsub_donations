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
    role                     :string
    timestamps
  end
  attr_accessible :wordpress_id, :user_email, :user_login, :display_name, :user_adress, :city, :country, :paymentid, :paypalid, :alternativeid, :user_phone, :donated_last_year_in_dkk, :role

  has_many :donations

  ROLES = [:administrator, :supporter, :subscriber, :author, :reviewer, :subadmin, :moderator]

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
