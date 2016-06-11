class PaypalEventsController < ApplicationController

  hobo_model_controller

  auto_actions :all, except: [:edit, :update, :new, :create]

  def index
    hobo_index PaypalEvent.order("created_at DESC")
  end

end
