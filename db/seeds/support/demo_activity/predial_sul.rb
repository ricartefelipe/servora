# frozen_string_literal: true

module Seeds
  module DemoActivity
    # A small amount of activity for Predial Sul (organization B), so tenant
    # isolation can be shown with data on both sides: the monthly elevator
    # inspection, planned and scheduled well within its deadline, and the
    # levelling call of the last business day, attended by Júlia this morning
    # (applied as its time comes, see Living).
    class PredialSul < Timeline
      PEOPLE = { igor: "igor@predial-sul.test", julia: "julia@predial-sul.test" }.freeze

      AURORA = "11222333000181"
      DEPOT = "Depósito Predial Sul"
      MARKER_RECEIPT = [DEPOT, "PEC-CABO-8", "Reposição de cabo de tração — NF 1187"].freeze

      EVENTS = [
        [:start, "09:00", :receive_stock, { by: :igor, warehouse: DEPOT, sku: MARKER_RECEIPT[1], quantity: "40",
                                            unit_cost: "21.4000", reason: MARKER_RECEIPT[2] }],
        [-1, "10:00", :open_order, { by: :igor, key: :inspection, customer: AURORA, location: "Torre A", priority: "low",
                                     origin: "email", service_type: "Inspeção de elevador", equipment: ["AS10-5512"],
                                     contact: "sindico@aurora.test", title: "Inspeção mensal dos elevadores — Torre A",
                                     problem: "Inspeção mensal prevista no contrato de manutenção do condomínio." }],
        [-1, "10:20", :schedule, { by: :igor, order: :inspection, on: 1, from: "09:00", to: "11:00", technicians: [:julia] }],
        [-1, "16:00", :open_order, { by: :igor, key: :leveling, customer: AURORA, location: "Torre A", priority: "high",
                                     origin: "phone", equipment: ["AS10-5512"], equipment_status: "attention",
                                     contact: "sindico@aurora.test", title: "Elevador social parando fora do nível",
                                     problem: "Moradores relatam um degrau de cerca de 3 cm no 4º andar." }],
        [-1, "16:20", :schedule, { by: :igor, order: :leveling, on: :today, from: "09:00", to: "11:00",
                                   technicians: [:julia] }],
        [:today, "08:30", :travel, { by: :julia, order: :leveling }],
        [:today, "09:05", :start, { by: :julia, order: :leveling }],
        [:today, "10:20", :report, { by: :julia, order: :leveling,
                                     diagnosis: "Sensor de nivelamento do 4º andar desalinhado e cabo de tração com " \
                                                "alongamento acima do previsto.",
                                     solution: "Sensor realinhado, cabo de tração ajustado e nivelamento conferido em " \
                                               "todos os andares." }],
        [:today, "10:40", :finish, { by: :julia, order: :leveling, outcome: "Nivelamento dentro de 5 mm em todos os andares." }],
        [:today, "11:00", :complete, { by: :igor, order: :leveling }]
      ].freeze
    end
  end
end
