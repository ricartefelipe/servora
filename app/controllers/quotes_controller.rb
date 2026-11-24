# frozen_string_literal: true

class QuotesController < TenantController
  STATUS_FILTERS = Quote::STATUSES.keys.freeze

  before_action :load_quote, except: %i[index new create]

  def index
    authorize Quote
    scope = policy_scope(current_organization.quotes).includes(:customer, :current_version).recent_first
    @status = params[:situacao].presence_in(STATUS_FILTERS) # rubocop:disable Rails/StrongParametersExpect -- optional filter
    scope = scope.where(status: @status) if @status
    @pagination = Pagination.new(scope, page: params[:pagina])
  end

  def show
    @version = @quote.current_version
    @items = @version.items.includes(:catalog_item).to_a
    @versions = @quote.versions.to_a
    @events = @quote.events.limit(30).to_a
    @catalog = policy_scope(current_organization.catalog_items).active.alphabetical if policy(@quote).edit_draft?
    @contacts = @quote.customer.contacts.approvers.alphabetical if policy(@quote).register_decision?
  end

  def new
    authorize Quote, :create?
    @customers = policy_scope(current_organization.customers).active.includes(:service_locations).alphabetical
  end

  def create
    authorize Quote, :create?
    attributes = params.expect(quote: %i[service_location_id title])
    location = tenant_relation(ServiceLocation).active.includes(:customer).find(attributes[:service_location_id])
    authorize location.customer, :show?
    quote = Quotes::Create.new(organization: current_organization, actor: current_membership, customer: location.customer,
      location:, title: attributes[:title].presence || "Orçamento de serviços").call
    redirect_to quote_path(quote), notice: "Orçamento #{quote.number} criado. Inclua os itens."
  end

  def update_terms
    authorize @quote, :edit_draft?
    terms = params.expect(terms: %i[valid_until discount payment_terms notes])
    Quotes::UpdateTerms.new(version: @quote.current_version, valid_until: terms[:valid_until], discount: terms[:discount],
      payment_terms: terms[:payment_terms], notes: terms[:notes]).call
    redirect_to quote_path(@quote), notice: "Condições atualizadas.", status: :see_other
  end

  def send_version
    authorize @quote
    version = Quotes::SendVersion.new(quote: @quote).call
    redirect_to quote_path(@quote), notice: "Versão #{version.version_number} enviada ao cliente.", status: :see_other
  end

  def new_version
    authorize @quote
    version = Quotes::NewVersion.new(quote: @quote).call
    redirect_to quote_path(@quote), notice: "Versão #{version.version_number} criada como rascunho.", status: :see_other
  end

  def cancel
    authorize @quote
    Quotes::Cancel.new(quote: @quote, reason: params.dig(:cancellation, :reason)).call
    redirect_to quote_path(@quote), notice: "Orçamento cancelado.", status: :see_other
  end

  def send_portal_link
    authorize @quote
    contact = tenant_relation(CustomerContact).includes(:customer).where(customer_id: @quote.customer_id)
      .find(params.expect(:contact_id))
    grant = Portal::IssueGrant.new(contact:, purpose: "quote_review", quote: @quote).call
    Portal::GrantDeliveryJob.perform_later(current_organization.id, grant.id)
    Quotes::History.record!(@quote, kind: "portal_link_sent", version: @quote.current_version, note: contact.name)
    redirect_to quote_path(@quote), notice: "Link de acesso enviado para #{contact.email}.", status: :see_other
  end

  rescue_from Servora::RuleViolation do |error|
    redirect_to quote_path(@quote), alert: error.message, status: :see_other
  end

  private

  def load_quote
    @quote = policy_scope(tenant_relation(Quote))
      .includes(:customer, :service_location, :created_by, :organization, :versions,
        current_version: [{ items: :catalog_item }, :decided_by_contact, { decided_by_membership: :user }])
      .find(params.expect(:id))
    authorize @quote, :show? if action_name == "show"
  end
end
