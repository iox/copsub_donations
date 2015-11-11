class WordpressPost< ActiveRecord::Base

  establish_connection "wordpress_database"
  self.table_name = "#{PREFIX}posts"

  attr_accessible :post_title, :post_status, :post_type

  after_initialize :default_values

  private

  # Avoid Mysql errors with NOT NULL columns
  def default_values
    self.post_content           ||= ''
    self.post_excerpt           ||= ''
    self.to_ping                ||= ''
    self.pinged                 ||= ''
    self.post_content_filtered  ||= ''
    self.post_date              ||= Time.now
    self.post_date_gmt          ||= Time.now
    self.post_modified          ||= Time.now
    self.post_modified_gmt      ||= Time.now
  end

end
