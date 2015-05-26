class WordpressUsermeta < ActiveRecord::Base

  establish_connection "wordpress_database"
  self.table_name = "#{PREFIX}usermeta"

  attr_accessible :user_id, :meta_key, :meta_value

end
