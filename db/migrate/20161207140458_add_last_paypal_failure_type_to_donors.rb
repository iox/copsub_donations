class AddLastPaypalFailureTypeToDonors < ActiveRecord::Migration
  def change
    add_column :donors, :last_paypal_failure_type, :string

    Donor.reset_column_information

    for event in PaypalEvent.where("txn_type IN ('recurring_payment_suspended_due_to_max_failed_payment', 'subscr_eot', 'subscr_failed', 'subscr_cancel')")
      event.store_last_paypal_failure
    end
  end
end
