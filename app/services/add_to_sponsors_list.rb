class AddToSponsorsList
  # This service adds the user to sponsors list in the website, if he was not already there

  def initialize(country, first_name, last_name)
    @country = country
    @first_name = first_name
    @last_name = last_name
  end

  def call
    return false if sponsor_already_exists?

    # Create a new sponsor post
    post = WordpressPost.new(post_title: "#{@first_name} #{@last_name}", post_status: 'publish', post_type: 'spons')
    post.save

    # Add the country to the post
    postmeta = WordpressPostmeta.create(post_id: post.id, meta_key: 'sponsor_country', meta_value: @country)

    # Add the post to the "Private Sponsor" category (hardcoded ID 276)
    term_relationship = WordpressTermRelationship.create(object_id: post.id, term_taxonomy_id: 276)

    return true
  end

  def sponsor_already_exists?
    WordpressPost.where("post_title LIKE ?", "%#{@first_name}%").where("post_title LIKE ?", "%#{@last_name}%").count > 0
  end
end