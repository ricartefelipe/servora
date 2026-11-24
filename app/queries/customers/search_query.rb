# frozen_string_literal: true

module Customers
  # Customer list filters. The term matches name/trade name (trigram index),
  # e-mail or document digits. All values are bound parameters.
  class SearchQuery
    STATUSES = %w[ativos arquivados todos].freeze

    def initialize(scope, term: nil, status: "ativos")
      @scope = scope
      @term = term.to_s.strip.first(80)
      @status = STATUSES.include?(status) ? status : "ativos"
    end

    def call
      relation = filter_status(@scope)
      relation = filter_term(relation) if @term.present?
      relation.alphabetical
    end

    private

    def filter_status(relation)
      case @status
      when "ativos" then relation.active
      when "arquivados" then relation.archived
      else relation
      end
    end

    def filter_term(relation)
      like = "%#{ActiveRecord::Base.sanitize_sql_like(@term)}%"
      digits = @term.gsub(/[^0-9A-Za-z]/, "").upcase
      conditions = relation.where(
        "customers.name ILIKE :like OR customers.trade_name ILIKE :like OR customers.email ILIKE :like", like:
      )
      conditions = conditions.or(relation.where("customers.document LIKE ?", "%#{digits}%")) if digits.length >= 3
      conditions
    end
  end
end
