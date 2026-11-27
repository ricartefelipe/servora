# frozen_string_literal: true

module Seeds
  # Customers of the demonstration organizations written by
  # 02_customers_and_equipment.rb. Kept apart from it so the story definitions
  # can be loaded without running a seed (Demo::AdvanceStoryJob): the routine
  # history draws its work from these customers' units.
  #
  # Equipment rows: [type, manufacturer, model, serial, location, status,
  # installed (months ago), warranty (months)].
  CUSTOMERS = {
    "a" => [
      { kind: "company", name: "Supermercado Horizonte Ltda.", trade_name: "Horizonte Supermercados", document: "45997418000153",
        email: "manutencao@horizonte.test", phone: "1133334444",
        locations: [["Loja Paulista", "Av. Paulista", "1500", "São Paulo", "SP", "01310200"],
                    ["Centro de distribuição", "Rod. Anhanguera, km 98", nil, "Campinas", "SP", "13065900"]],
        contacts: [["Paula Reis", "paula@horizonte.test", "Gerente de facilities", true]],
        equipment: [["Câmara fria", "Frigotech", "CF-900", "CF900-2231", "Centro de distribuição", "operational", 30, 36],
                    ["Split hi-wall", "LG", "S4-W24KL31A", "112KAUY9K587", "Loja Paulista", "attention", 18, 24],
                    ["Cassete", "Carrier", "40KWQB48C5", "4219C31207", "Loja Paulista", "operational", 8, 12]] },
      { kind: "individual", name: "Renato Albuquerque", document: "52998224725", email: "renato@cliente.test",
        locations: [["Residência", "Rua das Acácias", "45", "São Paulo", "SP", "04567010"]],
        contacts: [["Renato Albuquerque", "renato@cliente.test", "Proprietário", true]],
        equipment: [["Split piso-teto", "Carrier", "42XQV036515LC", "4216B27715", "Residência", "inoperative", 40, 36],
                    ["Split hi-wall", "Daikin", "FTKP09Q5VL", "E007412", "Residência", "operational", 26, 12]] }
    ],
    "b" => [
      { kind: "company", name: "Condomínio Edifício Aurora", document: "11222333000181", email: "sindico@aurora.test",
        locations: [["Torre A", "Rua Voluntários da Pátria", "800", "Porto Alegre", "RS", "90230010"]],
        contacts: [["Lúcia Andrade", "sindico@aurora.test", "Síndica", true]],
        equipment: [["Elevador", "Ascend", "AS-10", "AS10-5512", "Torre A", "operational", 50, 60]] }
    ]
  }.freeze
end
