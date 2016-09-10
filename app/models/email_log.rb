class EmailLog < ActiveRecord::Base

  hobo_model # Don't put anything above this

  fields do
    email   :string
    subject :string
    timestamps
  end
  attr_accessible :email, :subject

  # --- Permissions --- #

  def create_permitted?
    acting_user.administrator?
  end

  def update_permitted?
    acting_user.administrator?
  end

  def destroy_permitted?
    false
  end

  def view_permitted?(field)
    true
  end

end
