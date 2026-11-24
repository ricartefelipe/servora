# frozen_string_literal: true

class CatalogSearchQuery
  def initialize(scope, term: nil, kind: nil, include_inactive: false)
    @scope = scope
    @term = term.to_s.strip.first(80)
    @kind = kind
    @include_inactive = include_inactive
  end

  def call
    relation = @scope.alphabetical
    relation = relation.where(kind: @kind) if @kind
    relation = relation.active unless @include_inactive
    return relation if @term.blank?

    like = "%#{ActiveRecord::Base.sanitize_sql_like(@term)}%"
    relation.where("catalog_items.name ILIKE :like OR catalog_items.sku ILIKE :like", like:)
  end
end
