# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Pundit::Authorization

  default_form_builder ServoraFormBuilder

  allow_browser versions: :modern
  stale_when_importmap_changes

  before_action :assign_request_details
  before_action :configure_devise_parameters, if: :devise_controller?

  rescue_from Pundit::NotAuthorizedError, with: :render_forbidden
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  private

  def assign_request_details
    Current.request_id = request.request_id
    Current.ip_address = request.remote_ip
    Current.user_agent = request.user_agent.to_s.first(255)
    Current.user = current_user if user_signed_in?
  end

  def configure_devise_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:name])
    devise_parameter_sanitizer.permit(:account_update, keys: [:name])
  end

  def after_sign_in_path_for(user)
    stored_location_for(user) || organizations_path
  end

  # First page inside an organization: the field area for members who only
  # execute work orders, the audit trail for members who only audit, the
  # dashboard for everyone else.
  def landing_path_for(membership)
    if membership.field_only? then field_root_path
    elsif membership.audit_only? then audit_events_path
    else dashboard_path
    end
  end

  def after_sign_out_path_for(_scope)
    new_user_session_path
  end

  # Not found and forbidden responses are deliberately generic: they do not
  # reveal whether a record exists in another organization.
  def render_not_found
    render_error_page(404)
  end

  def render_forbidden
    render_error_page(403)
  end

  def render_error_page(code)
    @error = ErrorsController::PAGES.fetch(code)
    respond_to do |format|
      format.html { render "errors/show", layout: error_layout, status: code }
      format.turbo_stream do
        stream = turbo_stream.update("flash", partial: "shared/flash", locals: { flash_messages: { "alert" => @error.message } })
        render turbo_stream: stream, status: code
      end
      format.json { render json: { error: @error.title }, status: code }
      format.any { head code }
    end
  end

  def error_layout
    "application"
  end
end
