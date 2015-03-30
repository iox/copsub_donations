class WordpressUser < ActiveRecord::Base

  establish_connection "wordpress_database"
  self.table_name = "#{PREFIX}users"

  has_many :donations

  USERMETA_FIELDS = %w{alternative_id city country donation_method paymentid paypal_id user_phone}

  def additional_data
    data_fields = WordpressUser.find_by_sql("SELECT * FROM #{PREFIX}usermeta WHERE meta_key IN (#{USERMETA_FIELDS.map{|f|f.inspect}.join(',')})")
    result = Hash.new
    for field in data_fields
      result[field.meta_key] = field.meta_value
    end

    return result
  end

  def self.fuzzy_search(search)
    self.where("ID LIKE ? OR user_email LIKE ? OR user_login LIKE ? OR user_nicename LIKE ? OR display_name LIKE ?", "%#{search}%", "%#{search}%", "%#{search}%", "%#{search}%", "%#{search}%").limit(10)
  end

  def name
    self.inspect.to_s
  end

  def to_s
    name
  end

end