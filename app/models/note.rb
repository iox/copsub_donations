class Note < ActiveRecord::Base

  hobo_model # Don't put anything above this

  fields do
    body :text
    timestamps
  end
  attr_accessible :body, :donor, :donor_id
  
  belongs_to :donor

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
