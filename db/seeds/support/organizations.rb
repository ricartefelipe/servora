# frozen_string_literal: true

module Seeds
  # The two demonstration organizations, with fixed identifiers. Kept apart
  # from 01_organizations_and_people.rb (which writes them) so the story
  # definitions can be loaded without running a seed (Demo::AdvanceStoryJob).
  ORGANIZATIONS = {
    "a" => {
      id: "0193a000-0000-7000-8000-00000000000a", name: "Clima Norte Manutenção", legal_name: "Clima Norte Manutenção Ltda.",
      document: "11222333000181", segment: "hvac", travel_buffer_minutes: 30
    },
    "b" => {
      id: "0193b000-0000-7000-8000-00000000000b", name: "Predial Sul Serviços", legal_name: "Predial Sul Serviços Técnicos Ltda.",
      document: "45723174000110", segment: "building", travel_buffer_minutes: 20
    }
  }.freeze
end
