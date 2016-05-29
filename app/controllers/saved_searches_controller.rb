class SavedSearchesController < ApplicationController

  hobo_model_controller

  auto_actions :all, except: :show

  def new
    hobo_new do
      @saved_search.path ||= request.referrer.split('/').last
    end
  end

end
