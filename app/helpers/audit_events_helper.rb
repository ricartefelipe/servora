# frozen_string_literal: true

# Renders audit events for people: action labels (Audit::Labels) and the
# changeset as "Campo: de → para" lines (AuditEventsHelper::Changeset).
module AuditEventsHelper
  TRUNCATE_AT = 80

  def audit_action_label(key) = Audit::Labels.action(key)

  # Action filter options grouped by area; values stay the raw keys.
  def audit_action_options(keys, selected)
    grouped_options_for_select(Audit::Labels.grouped(keys), selected)
  end

  def audit_references(events) = Audit::ReferenceNames.load(events)

  def audit_changeset(event, references = Audit::ReferenceNames.new)
    changeset = Changeset.new(event, references)
    lines = changeset.entries.map { |entry| audit_change_line(entry) }
    omitted = changeset.sensitive_omitted?
    return tag.span("Sem detalhes", class: "text-ink-500") if lines.empty? && !omitted

    safe_join([
      (tag.dl(safe_join(lines), class: "space-y-1") if lines.any?),
      (tag.p("Valores sensíveis omitidos.", class: "mt-1 text-ink-500") if omitted)
    ].compact)
  end

  private

  def audit_change_line(entry)
    tag.div(class: "flex flex-wrap items-baseline gap-x-1.5") do
      tag.dt("#{entry.label}:", class: "font-medium text-ink-700") + tag.dd(audit_entry_value(entry), class: "m-0 text-ink-600")
    end
  end

  def audit_entry_value(entry)
    return audit_value_tag(entry.after) unless entry.pair

    parts = [
      audit_value_tag(entry.before),
      tag.span("→", class: "px-0.5 text-ink-500", aria: { hidden: true }),
      tag.span("para", class: "sr-only"),
      tag.span(audit_value_tag(entry.after), class: "text-ink-900")
    ]
    safe_join(parts, " ")
  end

  # "—" for empty values; long values are cut on screen, read in full by
  # screen readers and kept whole in the title.
  def audit_value_tag(text)
    return safe_join([tag.span("—", aria: { hidden: true }), tag.span("vazio", class: "sr-only")]) if text.nil?
    return text if text.length <= TRUNCATE_AT

    tag.span(title: text) do
      tag.span(text.truncate(TRUNCATE_AT, omission: "…"), aria: { hidden: true }) + tag.span(text, class: "sr-only")
    end
  end

  # Readable lines of one event's changeset. Technical fields, unresolvable
  # ids and credential-like fields are dropped; values are localized.
  class Changeset
    # One line; before is only meaningful when pair.
    Entry = Data.define(:label, :before, :after, :pair)

    EMPTY = "—"
    CHANGED = "alterada"
    SCALARS = { nil => nil, "" => nil, true => "Sim", false => "Não" }.freeze

    # Enumerations that are not owned by the audited record type.
    SHARED_VALUE_LABELS = {
      "role" => "Membership::ROLE_LABELS", "segment" => "Organization::SEGMENTS",
      "time_zone" => "Organization::TIME_ZONES", "priority" => "WorkOrder::PRIORITIES",
      "schedule_mode" => "MaintenancePlan::MODES", "category" => "Expense::CATEGORIES",
      "method" => "Payment::METHODS", "channel" => "Quotes::Decide::CHANNELS"
    }.freeze

    VALUE_LABELS = {
      "report" => { "ordens" => "Ordens de serviço", "produtividade" => "Produtividade",
                    "prazos" => "Prazos de atendimento", "financeiro" => "Financeiro", "materiais" => "Materiais" },
      "frequency_unit" => { "week" => "Semanas", "month" => "Meses", "year" => "Anos" },
      "membership.status" => { "active" => "Ativo", "deactivated" => "Desativado" }
    }.freeze

    MONEY_FIELDS = %w[amount unit_price total monthly_amount monthly_fee hourly_cost].freeze
    MINUTE_FIELDS = %w[estimated_minutes travel_buffer_minutes].freeze
    # "value" is the field used for { from:, to: } changesets.
    NUMERIC_FIELDS = (MONEY_FIELDS + MINUTE_FIELDS + %w[quantity delta value unit_cost iss_rate byte_size]).freeze
    ISO_DATE = /\A\d{4}-\d{2}-\d{2}\z/
    ISO_TIME = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/
    DECIMAL = /\A-?\d+(?:\.\d+)?\z/
    CONSTANT_NAME = /\A[A-Z][A-Z0-9_]*\z/
    # Same formats as ApplicationHelper#money, #unit_cost and #quantity.
    CURRENCY = { unit: "R$", separator: ",", delimiter: ".", format: "%u %n" }.freeze
    NUMBER = { separator: ",", delimiter: ".", strip_insignificant_zeros: true }.freeze

    def initialize(event, references = Audit::ReferenceNames.new)
      @event = event
      @references = references
      @changes = event.changeset.to_h.transform_keys(&:to_s)
      klass = event.auditable_type.to_s.safe_constantize
      @model = klass if klass.is_a?(Class) && klass < ActiveRecord::Base
    end

    def entries
      changes = @changes.dup
      lines = []
      lines << from_to_entry(changes) if changes.key?("from") && changes.key?("to")
      lines.concat(paired_entries(changes))
      lines.concat(changes.filter_map { |field, value| entry(field, value) })
    end

    # True when a credential-like field was left out of the readable lines.
    def sensitive_omitted?
      @changes.any? { |field, value| Audit::Labels.sensitive?(field) && !changed_marker?(value) }
    end

    def text(field, value)
      return SCALARS[value] if SCALARS.key?(value)

      case value
      when Array then list_text(field, value)
      when Hash then hash_text(value)
      when Numeric then number_text(field, value)
      when String then string_text(field, value)
      else value.to_s
      end
    end

    private

    def references = Audit::ReferenceNames::FIELDS.keys

    def diff?(value) = Audit::Labels.diff?(@event.action) && value.is_a?(Array) && value.size == 2

    # saved_changes store [before, after]; the marker sits in the after slot.
    def changed_marker?(value) = (diff?(value) ? value.last : value) == Audit::Labels::CHANGED_MARKER

    def field_label(field)
      key = "activerecord.attributes.#{@model&.model_name&.i18n_key}.#{field}"
      @model && I18n.exists?(key) ? @model.human_attribute_name(field) : Audit::Labels.field(field)
    end

    # { from:, to: } describes one change of the action's subject (status, period, minimum).
    # When both sides are equal only the value is shown, marked as unchanged.
    def from_to_entry(changes)
      label = Audit::Labels.from_to_label(@event.action)
      before = text("value", changes.delete("from"))
      after = text("value", changes.delete("to"))
      return Entry.new(label:, before: nil, after: "#{after} (sem alteração)", pair: false) if before == after

      Entry.new(label:, before:, after:, pair: true)
    end

    # from_location_id / to_location_id become one "Local: A → B" line.
    def paired_entries(changes)
      changes.keys.filter_map do |field|
        base = field[/\Afrom_(.+)\z/, 1]
        next unless base && changes.key?("to_#{base}")

        # Same rule as single fields: ids that cannot be named and credentials stay hidden.
        if Audit::Labels.hidden?(base, references:)
          changes.delete(field)
          changes.delete("to_#{base}")
          next
        end

        Entry.new(label: field_label(base), before: text(base, changes.delete(field)),
          after: text(base, changes.delete("to_#{base}")), pair: true)
      end
    end

    # A credential is never shown; the application only records that it changed.
    def entry(field, value)
      changed = changed_marker?(value)
      return if Audit::Labels.hidden?(field, references:) && !changed

      label = field_label(field)
      return Entry.new(label:, before: nil, after: CHANGED, pair: false) if changed
      return Entry.new(label:, before: nil, after: text(field, value), pair: false) unless diff?(value)

      diff_entry(field, label, value)
    end

    # [before, after] from saved changes; unchanged values are left out and a
    # creation shows only the new value.
    def diff_entry(field, label, value)
      before, after = value.map { |item| text(field, item) }
      return if before == after

      creation = @event.action.to_s.end_with?(".created")
      Entry.new(label:, before: (before unless creation), after:, pair: !creation)
    end

    def list_text(field, values)
      values.map { |item| text(field, item) || EMPTY }.join(", ").presence
    end

    def hash_text(hash)
      hash.filter_map do |key, item|
        "#{field_label(key)}: #{text(key.to_s, item) || EMPTY}" unless Audit::Labels.hidden?(key, references:)
      end.join("; ").presence
    end

    def string_text(field, value)
      return @references.name(field, value) || value if Audit::ReferenceNames.reference?(field)

      enum_label(field, value) || temporal_text(value) || decimal_text(field, value) || value
    end

    def enum_label(field, value)
      labels = value_labels(field)
      labels[value] if labels.is_a?(Hash)
    end

    def value_labels(field)
      VALUE_LABELS["#{@model&.model_name&.i18n_key}.#{field}"] || VALUE_LABELS[field] ||
        model_labels(field) || SHARED_VALUE_LABELS[field]&.safe_constantize
    end

    # Labels owned by the record type: KINDS for "kind", STATUSES for statuses.
    def model_labels(field)
      return unless @model

      names = ["#{field.upcase}_LABELS", field.pluralize.upcase]
      names << "STATUSES" if field == "value" || field.end_with?("status")
      name = names.find { |candidate| CONSTANT_NAME.match?(candidate) && @model.const_defined?(candidate, false) }
      @model.const_get(name, false) if name
    end

    def temporal_text(value)
      if ISO_DATE.match?(value)
        I18n.l(Date.iso8601(value))
      elsif ISO_TIME.match?(value)
        I18n.l(Time.zone.parse(value), format: :short)
      end
    rescue ArgumentError, RangeError
      nil
    end

    def decimal_text(field, value)
      number_text(field, BigDecimal(value)) if DECIMAL.match?(value) && NUMERIC_FIELDS.include?(field)
    end

    def number_text(field, value)
      case field
      when *MONEY_FIELDS then ActiveSupport::NumberHelper.number_to_currency(value, **CURRENCY)
      when "unit_cost" then ActiveSupport::NumberHelper.number_to_currency(value, **CURRENCY, precision: 4)
      when "iss_rate" then ActiveSupport::NumberHelper.number_to_percentage(value, **NUMBER, precision: 2)
      when "byte_size" then ActiveSupport::NumberHelper.number_to_human_size(value)
      when *MINUTE_FIELDS then "#{quantity(value)} min"
      else quantity(value)
      end
    end

    def quantity(value) = ActiveSupport::NumberHelper.number_to_rounded(value, **NUMBER, precision: 3)
  end
end
