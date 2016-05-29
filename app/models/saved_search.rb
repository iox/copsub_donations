class SavedSearch < ActiveRecord::Base

  hobo_model # Don't put anything above this

  fields do
    name :string, :required
    path :text, :required
    timestamps
  end
  attr_accessible :name, :path

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
