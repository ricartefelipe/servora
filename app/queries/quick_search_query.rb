# frozen_string_literal: true

# Quick search behind the command palette (Ctrl+K). The caller passes only the
# relations the member may read (the policy scopes of the authorized groups);
# each group reuses the filters of its index page and keeps the first matches.
# The term is always a bound parameter, never part of the SQL text.
class QuickSearchQuery
  MIN_LENGTH = 2
  MAX_LENGTH = 80
  LIMIT = 5

  GROUPS = {
    work_orders: "Ordens de serviço", customers: "Clientes", equipment: "Equipamentos", quotes: "Orçamentos"
  }.freeze

  Group = Data.define(:key, :label, :records)

  def self.normalize(term) = term.to_s.squish.first(MAX_LENGTH)
  def self.searchable?(term) = normalize(term).length >= MIN_LENGTH

  def initialize(term:, scopes:)
    @term = self.class.normalize(term)
    @scopes = scopes
  end

  # Groups with at least one match, in the fixed palette order.
  def call
    return [] unless self.class.searchable?(@term)

    GROUPS.filter_map do |key, label|
      scope = @scopes[key]
      next unless scope

      records = send(:"search_#{key}", scope).limit(LIMIT).to_a
      Group.new(key:, label:, records:) if records.any?
    end
  end

  private

  # Every status, not only open work: a number typed in the palette may belong
  # to a finished order. Most recent requests first.
  def search_work_orders(scope)
    WorkOrders::SearchQuery.new(scope.includes(:customer), status: WorkOrders::States.states, term: @term).call
      .reorder(requested_at: :desc, number: :desc)
  end

  def search_customers(scope)
    Customers::SearchQuery.new(scope, term: @term).call
  end

  def search_equipment(scope)
    EquipmentCatalog::SearchQuery.new(scope.includes(:customer), term: @term).call
  end

  def search_quotes(scope)
    like = "%#{ActiveRecord::Base.sanitize_sql_like(@term)}%"
    scope.includes(:customer).where("quotes.number ILIKE :like OR quotes.title ILIKE :like", like:).recent_first
  end
end
