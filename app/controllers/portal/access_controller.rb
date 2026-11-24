# frozen_string_literal: true

module Portal
  # GET only renders a confirmation page; the single-use grant is consumed by
  # the POST, so link previews and scanners cannot spend it.
  class AccessController < ActionController::Base # rubocop:disable Rails/ApplicationController
    layout "portal"

    helper_method :current_contact, :current_portal_organization

    rate_limit to: 20, within: 10.minutes, name: "portal-access",
      with: -> { render "portal/home/signed_out", status: :too_many_requests }

    def show
      @token = params[:token].to_s
      @organization_name = organization_name_for(@token)
      render "portal/home/signed_out", status: :not_found unless @organization_name
    end

    def create
      result = Portal::ExchangeGrant.new(token: params[:token].to_s, ip: request.remote_ip, user_agent: request.user_agent).call
      start_portal_session(result.session_token, result.session.expires_at)
      redirect_to(result.grant.quote_id ? portal_quote_path(result.grant.quote_id) : portal_root_path)
    rescue Servora::RuleViolation => e
      @message = e.message
      render "portal/home/signed_out", status: :unprocessable_content
    end

    private

    def start_portal_session(token, expires_at)
      reset_session
      cookies.signed[Portal::BaseController::COOKIE] = {
        value: token, httponly: true, secure: Rails.env.production?, same_site: :lax, expires: expires_at
      }
    end

    def current_contact = nil
    def current_portal_organization = nil

    def organization_name_for(token)
      organization_id = Portal::ExchangeGrant.organization_for(token)
      return nil unless organization_id

      Servora::Tenancy.with_organization(organization_id) { Organization.find(organization_id).name }
    end
  end
end
