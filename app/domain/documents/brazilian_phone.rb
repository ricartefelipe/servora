# frozen_string_literal: true

module Documents
  # Display mask for Brazilian phone numbers. Stored values are never changed:
  # anything that is not a recognizable Brazilian number is shown as typed.
  #
  #   "11987412035"      => "(11) 98741-2035"
  #   "+55 11 3333-4444" => "(11) 3333-4444"
  #   "08007771234"      => "0800 777 1234"
  module BrazilianPhone
    PATTERNS = [
      [/\A(0[3589]00)(\d{3})(\d{4})\z/, "%s %s %s"], # non-geographic (0800, 0300...)
      [/\A([1-9]{2})(9\d{4})(\d{4})\z/, "(%s) %s-%s"], # mobile with area code
      [/\A([1-9]{2})([2-8]\d{3})(\d{4})\z/, "(%s) %s-%s"], # landline with area code
      [/\A(9\d{4})(\d{4})\z/, "%s-%s"], # mobile without area code
      [/\A([2-8]\d{3})(\d{4})\z/, "%s-%s"] # landline without area code
    ].freeze

    module_function

    def format(value)
      original = value.to_s.strip
      return original if original.empty?

      digits = national_digits(original)
      return original if digits.nil?

      mask(digits) || original
    end

    # Digits without the country code (+55) and the trunk prefix (0), or nil
    # when the number carries another country code.
    def national_digits(value)
      return nil if value.start_with?("+") && !value.start_with?("+55")

      digits = value.gsub(/\D/, "")
      return digits if digits.match?(/\A0[3589]00\d{7}\z/)

      without_trunk_prefix(without_country_code(digits))
    end

    def without_country_code(digits)
      [12, 13].include?(digits.length) && digits.start_with?("55") ? digits.delete_prefix("55") : digits
    end

    def without_trunk_prefix(digits)
      [11, 12].include?(digits.length) && digits.start_with?("0") ? digits.delete_prefix("0") : digits
    end

    def mask(digits)
      PATTERNS.each do |pattern, template|
        match = pattern.match(digits)
        return Kernel.format(template, *match.captures) if match
      end
      nil
    end
  end
end
