# frozen_string_literal: true

# Service types with the checklists required to complete work orders.
module Seeds
  SERVICE_TYPES = {
    "a" => {
      "Manutenção preventiva de split" => [
        ["Pressão de sucção (psi)", "number", true], ["Limpeza de filtros e serpentina", "check", true],
        ["Dreno desobstruído", "check", true], ["Corrente do compressor (A)", "number", true], ["Observações", "text", false]
      ],
      "Atendimento corretivo" => [
        ["Equipamento testado após o reparo", "check", true], ["Cliente orientado sobre o uso", "check", true]
      ]
    },
    "b" => {
      "Inspeção de elevador" => [["Freio de segurança testado", "check", true], ["Nivelamento nos andares", "check", true]]
    }
  }.freeze

  def self.service_types(key)
    organization_id = ORGANIZATIONS.fetch(key)[:id]
    Servora::Tenancy.with_organization(organization_id) do
      organization = Organization.find(organization_id)
      SERVICE_TYPES.fetch(key).each { |name, items| seed_service_type(organization, name, items) }
    end
  end

  def self.seed_service_type(organization, name, items)
    return if organization.service_types.exists?(name:)

    service_type = organization.service_types.new(name:)
    items.each_with_index do |(label, kind, required), index|
      service_type.checklist_items.build(organization:, label:, response_kind: kind, required:, position: index + 1)
    end
    service_type.save!
  end
end

Seeds.service_types("a")
Seeds.service_types("b")
puts "Tipos de serviço de demonstração prontos."
