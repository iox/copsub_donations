class RoleChange < ActiveRecord::Base

  hobo_model # Don't put anything above this

  fields do
    previous_role :string
    new_role      :string
    timestamps
  end
  attr_accessible :previous_role, :new_role, :donor_id, :donor

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
