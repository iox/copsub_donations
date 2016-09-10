class EmailLogsController < ApplicationController

  hobo_model_controller

  auto_actions :all, except: [:edit, :new, :destroy, :create, :update, :show]

end
