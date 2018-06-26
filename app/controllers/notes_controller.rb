class NotesController < ApplicationController

  hobo_model_controller

  auto_actions :all, except: [:show, :edit, :index]

  auto_actions_for :donor, [:create]
  
end
