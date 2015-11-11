class WordpressPostmeta < ActiveRecord::Base

  establish_connection "wordpress_database"
  self.table_name = "#{PREFIX}postmeta"

  attr_accessible :post_id, :meta_key, :meta_value

end
