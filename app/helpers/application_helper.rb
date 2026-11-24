# frozen_string_literal: true

module ApplicationHelper
  # Opaque key identifying the user + organization context of the page. The
  # browser purges locally stored drafts whenever it changes (logout, switch).
  def local_context_key
    return "anonimo" unless respond_to?(:user_signed_in?) && user_signed_in?

    material = "#{current_user.id}:#{session[TenantController::ORGANIZATION_SESSION_KEY]}"
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, material).first(24)
  end

  def money(value)
    number_to_currency(value || 0, unit: "R$", separator: ",", delimiter: ".", format: "%u %n")
  end

  # Unit costs keep 4 decimals (moving average precision).
  def unit_cost(value)
    number_to_currency(value || 0, unit: "R$", separator: ",", delimiter: ".", precision: 4, format: "%u %n")
  end

  def quantity(value, unit = nil)
    formatted = number_with_precision(value || 0, precision: 3, strip_insignificant_zeros: true, separator: ",", delimiter: ".")
    [formatted, unit].compact_blank.join(" ")
  end

  def date_time(value)
    value ? l(value, format: :short) : "—"
  end

  def date(value)
    value ? l(value.to_date) : "—"
  end
end
