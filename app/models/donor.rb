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
    paymentid                :integer
    paypal_id                :integer
    user_phone               :string
    donated_last_year_in_dkk :integer
    role                     :string
    timestamps
  end
  attr_accessible :wordpress_id, :user_email, :user_login, :display_name, :user_adress, :city, :country, :paymentid, :paypal_id, :user_phone, :donated_last_year_in_dkk, :role

  has_many :donations

  ROLES = [:administrator, :supporter, :subscriber, :author, :reviewer, :subadmin, :moderator]

  # Other user fields which we might enable in the future: user_nicename
  USER_FIELDS = %w{ID user_email user_login display_name}
  # Other usermeta fields which we might enable in the future: alternative_id nickname donation_method
  USERMETA_FIELDS = %w{user_adress city country paymentid paypal_id user_phone donated_last_year_in_dkk}

  ALL_FIELDS = USER_FIELDS + USERMETA_FIELDS + ['role']


  # This scope method allows to search for users using several fields, for example "WordpressUser.fuzzy_search('ignacio')"
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
