class WordpressUser < ActiveRecord::Base

  establish_connection "wordpress_database"
  self.table_name = "#{PREFIX}users"

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