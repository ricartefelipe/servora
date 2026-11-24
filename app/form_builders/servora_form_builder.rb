# frozen_string_literal: true

# Accessible form fields: every input has a label, errors are linked through
# aria-describedby and aria-invalid, hints are announced with the field.
class ServoraFormBuilder < ActionView::Helpers::FormBuilder
  INPUT_CLASS = "sv-input"
  BUTTON_VARIANTS = {
    primary: "sv-btn-primary", secondary: "sv-btn-secondary", ghost: "sv-btn-ghost", danger: "sv-btn-danger", dark: "sv-btn-dark"
  }.freeze

  def field(attribute, label: nil, hint: nil, as: :text_field, wrapper: {}, **options)
    wrap(attribute, label:, hint:, wrapper:) do |aria|
      public_send(as, attribute, input_options(options, aria))
    end
  end

  def select_field(attribute, choices, label: nil, hint: nil, include_blank: false, wrapper: {}, **options)
    wrap(attribute, label:, hint:, wrapper:) do |aria|
      select(attribute, choices, { include_blank: }, input_options(options, aria))
    end
  end

  def text_area_field(attribute, label: nil, hint: nil, rows: 4, wrapper: {}, **options)
    wrap(attribute, label:, hint:, wrapper:) do |aria|
      text_area(attribute, input_options(options.merge(rows:), aria))
    end
  end

  def toggle_field(attribute, label:, hint: nil, **options)
    @template.tag.div(class: "flex items-start gap-3") do
      check_box(attribute, options.merge(class: "mt-1 size-4 rounded border-ink-400")) +
        @template.tag.div do
          label(attribute, label, class: "text-sm font-medium text-ink-800") +
            (hint ? @template.tag.p(hint, class: "sv-hint mt-0.5") : ActiveSupport::SafeBuffer.new)
        end
    end
  end

  def submit_button(text = nil, variant: :primary, **options)
    css = [BUTTON_VARIANTS.fetch(variant.to_sym), options.delete(:class)].compact.join(" ")
    button(text || submit_default_value, { type: "submit", class: css, data: { turbo_submits_with: "Salvando…" } }.merge(options))
  end

  def error_summary
    return ActiveSupport::SafeBuffer.new if object.nil? || object.errors.empty?

    @template.render("shared/form_errors", errors: object.errors)
  end

  private

  def wrap(attribute, label:, hint:, wrapper:)
    ids = FieldIds.new(field_id(attribute))
    messages = error_messages(attribute)
    aria = { invalid: messages.any? || nil, describedby: ids.described_by(hint:, errors: messages.any?) }.compact

    @template.tag.div(**wrapper) do
      label(attribute, label, class: "sv-label") + yield(aria) + hint_tag(hint, ids.hint) + error_tag(messages, ids.error)
    end
  end

  FieldIds = Data.define(:base) do
    def hint = "#{base}_hint"
    def error = "#{base}_error"

    def described_by(hint:, errors:)
      [(self.hint if hint), (error if errors)].compact.join(" ").presence
    end
  end

  def error_messages(attribute)
    object.respond_to?(:errors) ? object.errors.full_messages_for(attribute) : []
  end

  def hint_tag(hint, id)
    hint ? @template.tag.p(hint, id:, class: "sv-hint") : ActiveSupport::SafeBuffer.new
  end

  def error_tag(messages, id)
    messages.any? ? @template.tag.p(messages.to_sentence, id:, class: "sv-error") : ActiveSupport::SafeBuffer.new
  end

  def input_options(options, aria)
    css = [INPUT_CLASS, options.delete(:class)].compact.join(" ")
    options.merge(class: css, aria: aria.merge(options.fetch(:aria, {})))
  end
end
