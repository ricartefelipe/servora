# frozen_string_literal: true

class PortalMailer < ApplicationMailer
  def access(grant:, token:)
    @grant = grant
    @contact = grant.contact
    @organization = grant.organization
    @quote = grant.quote
    @url = portal_access_url(token)
    mail(to: @contact.email, subject:)
  end

  private

  def subject
    return "Acesso ao portal de #{@organization.name}" unless @quote

    "Proposta #{@quote.number} de #{@organization.name} aguarda sua análise"
  end
end
