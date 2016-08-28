class RoleChangesController < ApplicationController

  hobo_model_controller

  auto_actions :index

  def index
    params[:search] ||= ""
    params[:sort] ||= "id"
    params[:direction] ||= "desc"

    @role_changes = role_changes_scope.order("#{params[:sort]} #{params[:direction]}").paginate(:page => params[:page])

    respond_to do |format|
      format.html
    end
  end

  private

  def role_changes_scope
    scope = RoleChange.all

    if params[:created_at] && !params[:created_at_from].blank? && !params[:created_at_to].blank?
      scope = scope.where("created_at BETWEEN ? AND ?", params[:created_at_from].to_date, params[:created_at_to].to_date)
    end

    return scope
  end

end