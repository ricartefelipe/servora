# frozen_string_literal: true

module Audit
  # Names of the records an audit changeset points to (technician, contact,
  # location...), so the trail shows "Bruno Lima" instead of an id. Loads a
  # page of events with one query per kind, restricted to the events'
  # organization on top of RLS.
  class ReferenceNames
    # Changeset field (also as from_<field>/to_<field>) => kind of record.
    FIELDS = {
      "membership_id" => :membership, "custodian_membership_id" => :membership, "technicians" => :membership,
      "user_id" => :user, "contact_id" => :contact, "customer_id" => :customer,
      "service_location_id" => :location, "location_id" => :location
    }.freeze
    UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

    def self.load(events)
      ids = Hash.new { |hash, kind| hash[kind] = Set.new }
      events.each do |event|
        event.changeset.to_h.each { |field, value| collect(ids, kind_for(field.to_s.sub(/\A(?:from|to)_/, "")), value) }
      end
      organization_id = events.first&.organization_id
      new(ids.to_h { |kind, set| [kind, names(kind, set.to_a, organization_id)] })
    end

    def self.kind_for(field) = FIELDS[field.to_s]
    def self.reference?(field) = FIELDS.key?(field.to_s)

    def self.collect(ids, kind, value)
      return unless kind

      Array(value).flatten.each { |id| ids[kind] << id if id.is_a?(String) && UUID.match?(id) }
    end

    def self.names(kind, ids, organization_id)
      return {} if ids.empty?

      case kind
      when :membership then member_names(Membership.where(organization_id:, id: ids), :id)
      when :user then member_names(Membership.where(organization_id:, user_id: ids), :user_id)
      else model_for(kind).where(organization_id:, id: ids).pluck(:id, :name).to_h
      end
    end

    def self.member_names(scope, key) = scope.includes(:user).to_h { |member| [member.public_send(key), member.user.name] }
    def self.model_for(kind) = { contact: CustomerContact, customer: Customer, location: ServiceLocation }.fetch(kind)

    private_class_method :collect, :names, :member_names, :model_for

    def initialize(names = {})
      @names = names
    end

    # nil when the value is not an id; the record may be gone or out of reach.
    def name(field, id)
      kind = self.class.kind_for(field)
      return unless kind && id.is_a?(String) && UUID.match?(id)

      @names.fetch(kind, {}).fetch(id, "registro indisponível")
    end
  end
end
