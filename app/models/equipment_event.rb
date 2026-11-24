# frozen_string_literal: true

# Immutable history entry of a piece of equipment.
class EquipmentEvent < TenantRecord
  KIND_LABELS = {
    "registered" => "Cadastrado",
    "relocated" => "Mudança de local",
    "ownership_transferred" => "Transferência de proprietário",
    "status_changed" => "Mudança de estado",
    "archived" => "Arquivado",
    "restored" => "Reativado",
    "maintenance" => "Manutenção"
  }.freeze

  belongs_to :equipment, inverse_of: :events

  validates :kind, inclusion: { in: KIND_LABELS.keys }

  def readonly? = persisted?
  def kind_label = KIND_LABELS.fetch(kind)
end
