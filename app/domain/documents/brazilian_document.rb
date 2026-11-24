# frozen_string_literal: true

module Documents
  # CPF and CNPJ validation and formatting.
  #
  # CNPJ accepts the alphanumeric format adopted from July 2026: twelve
  # characters in [0-9A-Z] followed by two numeric check digits. Each character
  # contributes (ASCII code - 48) to the modulo-11 calculation, which keeps
  # numeric CNPJs valid under the same algorithm.
  module BrazilianDocument
    CPF_WEIGHTS = [(2..10).to_a.reverse, (2..11).to_a.reverse].freeze
    CNPJ_WEIGHTS = [[5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2], [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]].freeze

    module_function

    def normalize(value)
      value.to_s.upcase.gsub(/[^0-9A-Z]/, "")
    end

    def kind(value)
      normalized = normalize(value)
      if cpf?(normalized) then :cpf
      elsif cnpj?(normalized) then :cnpj
      end
    end

    def valid?(value)
      !kind(value).nil?
    end

    def cpf?(digits)
      return false unless digits.match?(/\A\d{11}\z/)
      return false if digits.chars.uniq.one?

      numbers = digits.chars.map(&:to_i)
      check_digit(numbers.first(9), CPF_WEIGHTS[0]) == numbers[9] &&
        check_digit(numbers.first(10), CPF_WEIGHTS[1]) == numbers[10]
    end

    def cnpj?(value)
      return false unless value.match?(/\A[0-9A-Z]{12}\d{2}\z/)
      return false if value.chars.uniq.one?

      values = value.chars.map { |char| char.ord - 48 }
      check_digit(values.first(12), CNPJ_WEIGHTS[0]) == values[12] &&
        check_digit(values.first(13), CNPJ_WEIGHTS[1]) == values[13]
    end

    def format(value)
      normalized = normalize(value)
      case kind(normalized)
      when :cpf then normalized.sub(/\A(\d{3})(\d{3})(\d{3})(\d{2})\z/, '\1.\2.\3-\4')
      when :cnpj then normalized.sub(/\A(.{2})(.{3})(.{3})(.{4})(\d{2})\z/, '\1.\2.\3/\4-\5')
      else value.to_s
      end
    end

    def check_digit(values, weights)
      remainder = values.zip(weights).sum { |value, weight| value * weight } % 11
      remainder < 2 ? 0 : 11 - remainder
    end
  end
end
