class WordpressUser < ActiveRecord::Base

  establish_connection "wordpress_database"
  self.table_name = "#{PREFIX}users"

  has_many :donations

  def name
    self.inspect.to_s
  end

  def to_s
    name
  end

  def donated_last_year_in_dkk
    donations.where("donated_at > '#{(Date.today-1.year).to_time.to_s(:db)}'").sum(:amount_in_dkk)
  end

  # Other user fields which we might enable in the future: user_nicename
  USER_FIELDS = %w{ID user_email user_login display_name}
  # Other usermeta fields which we might enable in the future: alternative_id nickname donation_method
  USERMETA_FIELDS = %w{user_adress city country paymentid paypal_id user_phone}

  ALL_FIELDS = USER_FIELDS + USERMETA_FIELDS + ['role']

  ROLES = [:administrator, :supporter, :subscriber, :author, :reviewer, :subadmin, :moderator]

  #################################
  # Code related to editing users #
  #################################

  attr_accessible *ALL_FIELDS

  USERMETA_FIELDS.each do |attr|
    define_method("#{attr}=") do |val|
      meta = WordpressUsermeta.where(:user_id => self.id).where(meta_key: attr).first
      if meta
        meta.update_attribute(:meta_value, val)
      else
        WordpressUsermeta.create(user_id: self.id, meta_key: attr, meta_value: val)
      end
    end
  end

  # In Wordpress, the roles are stores using a serialized hash with the form {"administrator" => true}
  def role
    db_value = read_attribute("role")
    begin
      db_value ? PHP.unserialize(db_value).keys.join(', ') : nil
    rescue
      db_value
    end
  end

  def role=(val)
    db_hash = {val => true}
    db_value = PHP.serialize(db_hash)
    meta = WordpressUsermeta.where(:user_id => self.id).where(meta_key: "#{PREFIX}capabilities").first
    if meta
      meta.update_attribute(:meta_value, db_value)
    else
      Rails.logger.info "Could not find the usermeta capabilities record for the user #{self.id}"
    end
  end

  # Small hack to ensure that editing users works
  def editable_by?(someone, something)
    true
  end




  #################################
  #      Scopes and searches      #
  #################################

  # This scope method allows to search for users using several fields, for example "WordpressUser.fuzzy_search('ignacio')"
  def self.fuzzy_search(search)
    # Build a string like: "ID LIKE :search OR user_email LIKE :search ..."
    sql_user_fields = USER_FIELDS.map{|f|"#{PREFIX}users.#{f} LIKE :search"}.join(" OR ")
    sql_user_fields += " OR " + USERMETA_FIELDS.map{|f|"#{f}.meta_value LIKE :search"}.join(" OR ")

    # If the user searches for "Ignacio Hedehusene", then
    # we'll search for records that match the two words, even in different DB fields
    scope = self.with_all_fields
    for string in search.split(" ")
      # Search in the DB, limiting the number of results
      scope = scope.where(sql_user_fields, :search => "%#{string}%")
    end

    return scope
  end

  # This scope method returns all fields from the usermeta table + the amount donated last year
  def self.with_all_fields
    scope = self

    for field in USERMETA_FIELDS
      scope = scope.joins("LEFT JOIN #{PREFIX}usermeta #{field} ON #{PREFIX}users.id = #{field}.user_id AND #{field}.meta_key = '#{field}'")
    end

    # Parse the capabilities field to get the user role + ["#{PREFIX}capabilities"]
    scope = scope.joins("LEFT JOIN #{PREFIX}usermeta #{PREFIX}capabilities ON #{PREFIX}users.id = #{PREFIX}capabilities.user_id AND #{PREFIX}capabilities.meta_key = '#{PREFIX}capabilities'")

    return scope.select("distinct #{PREFIX}users.*, " + USERMETA_FIELDS.map{|f| "#{f}.meta_value AS #{f}"}.join(', ') + ", #{PREFIX}capabilities.meta_value AS role")
  end

  def self.name_attribute
    name
  end

end