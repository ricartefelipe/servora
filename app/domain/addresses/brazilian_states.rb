# frozen_string_literal: true

module Addresses
  # Federative units and postal code (CEP) helpers.
  module BrazilianStates
    STATES = {
      "AC" => "Acre", "AL" => "Alagoas", "AP" => "Amapá", "AM" => "Amazonas", "BA" => "Bahia", "CE" => "Ceará",
      "DF" => "Distrito Federal", "ES" => "Espírito Santo", "GO" => "Goiás", "MA" => "Maranhão", "MT" => "Mato Grosso",
      "MS" => "Mato Grosso do Sul", "MG" => "Minas Gerais", "PA" => "Pará", "PB" => "Paraíba", "PR" => "Paraná",
      "PE" => "Pernambuco", "PI" => "Piauí", "RJ" => "Rio de Janeiro", "RN" => "Rio Grande do Norte",
      "RS" => "Rio Grande do Sul", "RO" => "Rondônia", "RR" => "Roraima", "SC" => "Santa Catarina", "SP" => "São Paulo",
      "SE" => "Sergipe", "TO" => "Tocantins"
    }.freeze

    module_function

    def valid?(code) = STATES.key?(code.to_s.upcase)

    def normalize_postal_code(value)
      digits = value.to_s.gsub(/\D/, "")
      digits.presence
    end

    def format_postal_code(value)
      digits = normalize_postal_code(value)
      digits&.match?(/\A\d{8}\z/) ? "#{digits[0, 5]}-#{digits[5, 3]}" : value.to_s
    end
  end
end
