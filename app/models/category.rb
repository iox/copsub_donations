class Category < ActiveRecord::Base

  hobo_model # Don't put anything above this

  fields do
    name :string, :required
    default :boolean, :default => false
    timestamps
  end
  attr_accessible :name, :donations, :default

  has_many :donations, :dependent => :destroy

  set_default_order "name asc"

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
