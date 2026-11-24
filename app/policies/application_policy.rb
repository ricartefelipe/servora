# frozen_string_literal: true

# Deny-by-default base policy. Subclasses grant actions through explicit
# permissions from Authorization::Permissions.
class ApplicationPolicy
  attr_reader :context, :record

  delegate :can?, :membership, :user, :organization, :technician?, to: :context

  def initialize(context, record)
    @context = context
    @record = record
  end

  def index? = false
  def show? = false
  def create? = false
  def new? = create?
  def update? = false
  def edit? = update?
  def destroy? = false

  class Scope
    attr_reader :context, :scope

    delegate :can?, :membership, to: :context

    def initialize(context, scope)
      @context = context
      @scope = scope
    end

    def resolve
      raise NotImplementedError, "#{self.class} must implement #resolve"
    end
  end
end
