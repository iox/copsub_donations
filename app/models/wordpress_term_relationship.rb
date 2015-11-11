class WordpressTermRelationship < ActiveRecord::Base

  establish_connection "wordpress_database"
  self.table_name = "#{PREFIX}term_relationships"

  attr_accessible :object_id, :term_taxonomy_id

end
