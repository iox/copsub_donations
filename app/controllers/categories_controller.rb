class CategoriesController < ApplicationController

  hobo_model_controller

  auto_actions :all, except: [:new, :show]

  def index
    hobo_index Category.order("name asc")
  end

end
