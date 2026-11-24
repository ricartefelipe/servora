# frozen_string_literal: true

module Portal
  # Base of the customer portal. Authentication is independent from staff
  # accounts: a signed HttpOnly cookie carries the portal session token, whose
  # digest resolves the organization (SECURITY DEFINER, tenant id only); the
  # session and contact are then loaded under RLS and re-validated on every
  # request (active, not expired, portal still enabled, customer not archived).
  # Deliberately not ApplicationController: staff authentication (Devise),
  # tenant selection and staff policies must not apply to portal requests.
  class BaseController < ActionController::Base # rubocop:disable Rails/ApplicationController
    COOKIE = :servora_portal

    layout "portal"

    before_action :assign_request_details
    around_action :within_portal_session

    rescue_from ActiveRecord::RecordNotFound do
      render "portal/home/not_found", status: :not_found
    end

    helper_method :current_contact, :current_portal_organization

    private

    attr_reader :current_contact, :current_portal_session

    def current_portal_organization = current_contact&.organization

    def assign_request_details
      Current.request_id = request.request_id
      Current.ip_address = request.remote_ip
    end

    def within_portal_session(&)
      token = cookies.signed[COOKIE]
      organization_id = Portal::Authenticate.organization_for(token)
      return deny_access unless organization_id

      Servora::Tenancy.with_organization(organization_id) do
        session = PortalSession.includes(contact: %i[customer organization])
          .find_by(token_digest: PortalAccessGrant.digest(token))
        next deny_access unless valid_session?(session)

        session.update_column(:last_seen_at, Time.current) if session.last_seen_at < 5.minutes.ago # rubocop:disable Rails/SkipsModelValidations
        @current_portal_session = session
        @current_contact = session.contact
        Current.set(portal_contact: @current_contact, organization: @current_contact.organization) do
          Time.use_zone(@current_contact.organization.zone, &)
        end
      end
    end

    def valid_session?(session)
      return false unless session&.active?

      contact = session.contact
      contact.portal_enabled? && !contact.archived? && !contact.customer.archived? && contact.organization.active?
    end

    def deny_access
      cookies.delete(COOKIE)
      render "portal/home/signed_out", status: :unauthorized
    end

    def customer_scope(relation)
      relation.where(customer_id: current_contact.customer_id)
    end
  end
end
