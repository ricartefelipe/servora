# frozen_string_literal: true

module Seeds
  module DemoActivity
    # History of Clima Norte (organization A): about six weeks of routine work
    # (History), then the recent days written by hand — an overdue bill, a
    # quote approved and executed by the team, an order waiting for a part,
    # the requests of the last business day (one of them through the portal,
    # after hours, waiting for triage) and today's work for Diego, Eduarda and
    # Fábio, which goes on through the day (Living). See docs/DEMO.md ("Dados
    # pré-carregados" and "O que muda ao longo do dia").
    class ClimaNorte < Timeline
      include History

      PEOPLE = {
        bruno: "bruno@clima-norte.test", carla: "carla@clima-norte.test", diego: "diego@clima-norte.test",
        eduarda: "eduarda@clima-norte.test", fabio: "fabio@clima-norte.test", gabriela: "gabriela@clima-norte.test"
      }.freeze

      HORIZONTE = "45997418000153"
      RENATO = "52998224725"
      CLINICA = "27183456000190"
      RESTAURANTE = "38492617000144"
      ACADEMIA = "61384257000189"
      PRISMA = "72915348000110"
      PATRICIA = "38195602460"
      PEQUENO_SABER = "64820593000115"
      CENTRAL = "Almoxarifado central"
      VAN = "Van 01 — Diego"
      CORRECTIVE = "Atendimento corretivo"
      PREVENTIVE = "Manutenção preventiva de split"
      INSTALLATION = "Instalação de equipamento"
      RELAY = "PEC-RELE-220"
      REFRIGERATION = %i[diego eduarda].freeze
      ELECTRICAL = %i[diego fabio].freeze

      # Parts bought back every week (History#restocking); the start relay is
      # bought only when an order needs it.
      RESTOCKED = %w[PEC-CAP-355 PEC-R410A PEC-FILTRO-14 PEC-CONTATOR-32 PEC-DISJ-20 PEC-MOTOR-VENT PEC-BOMBA-DRENO
                     PEC-ISOL-38 PEC-R32 PEC-SENSOR-NTC].freeze

      MARKER_RECEIPT = [CENTRAL, "PEC-R410A", "Reposição de gás refrigerante — NF 4312"].freeze

      # Equipment: [type, manufacturer, model, serial, location, status, installed (months ago), warranty (months)].
      CUSTOMERS = [
        { kind: "company", name: "Clínica Vida Plena Ltda.", trade_name: "Clínica Vida Plena", document: CLINICA,
          email: "administrativo@vidaplena.test", phone: "1135550101",
          locations: [["Unidade Moema", "Av. Ibirapuera", "2120", "São Paulo", "SP", "04028001"]],
          contacts: [["Marina Lopes", "marina@vidaplena.test", "Gerente administrativa", true]],
          equipment: [["Split hi-wall", "Daikin", "FTKP12Q5VL", "E006731", "Unidade Moema", "operational", 11, 12],
                      ["Split hi-wall", "Daikin", "FTKP18Q5VL", "E006748", "Unidade Moema", "operational", 26, 36]] },
        { kind: "company", name: "Restaurante Sabor da Serra Ltda.", trade_name: "Sabor da Serra", document: RESTAURANTE,
          email: "compras@saborserra.test", phone: "1136660202",
          locations: [["Matriz", "Rua Augusta", "980", "São Paulo", "SP", "01304001"]],
          contacts: [["Rafael Teixeira", "rafael@saborserra.test", "Sócio-gerente", true]],
          equipment: [["Câmara fria", "Frigotech", "CF-600", "CF600-1187", "Matriz", "operational", 14, 24],
                      ["Split piso-teto", "Carrier", "42XQV060515LC", "4216B42218", "Matriz", "operational", 5, 12]] },
        { kind: "company", name: "Academia Movimento Fitness Ltda.", trade_name: "Academia Movimento", document: ACADEMIA,
          email: "unidade.vilamariana@movimento.test", phone: "1137770303",
          locations: [["Unidade Vila Mariana", "Rua Domingos de Morais", "1450", "São Paulo", "SP", "04010100"]],
          contacts: [["Tiago Moreira", "tiago@movimento.test", "Gerente da unidade", true]],
          equipment: [["Split hi-wall", "LG", "S4-W24KL31A", "112KAUY9M204", "Unidade Vila Mariana", "operational", 20, 24],
                      ["Split hi-wall", "LG", "S4-W24KL31A", "112KAUY9M211", "Unidade Vila Mariana", "operational", 20, 24],
                      ["Split piso-teto", "Springer Midea", "42ZQVA60M5", "4251880E0127", "Unidade Vila Mariana",
                       "operational", 9, 12]] },
        { kind: "company", name: "Prisma Contabilidade e Consultoria Ltda.", trade_name: "Prisma Contabilidade",
          document: PRISMA, email: "administrativo@prisma.test", phone: "1138880404",
          locations: [["Sede", "Av. Brigadeiro Faria Lima", "2200", "São Paulo", "SP", "01452000"]],
          contacts: [["Helena Duarte", "helena@prisma.test", "Coordenadora administrativa", true]],
          equipment: [["Cassete", "Daikin", "FCQ36AVL", "E009212", "Sede", "operational", 16, 36],
                      ["Cassete", "Daikin", "FCQ36AVL", "E009227", "Sede", "operational", 16, 36],
                      ["Split hi-wall", "Samsung", "AR12BVFAMWK", "0FD4PAEN400589P", "Sede", "operational", 3, 12]] }
      ].freeze

      # The first suitable visit of the routine history (HistoryPlan): the only
      # start relay used before the one reserved for the order waiting for parts.
      HISTORY_SPECIALS = [
        { kind: :corrective, template: :relay, customer: RESTAURANTE, location: "Matriz", equipment: ["CF600-1187"],
          service_type: :corrective, crew: :electrical, minutes: 90, customer_kind: "company",
          contact: "rafael@saborserra.test", title: "Compressor da câmara fria da cozinha sem partir",
          problem: "A câmara fria parou durante a madrugada; o compressor não arma.",
          diagnosis: "Relé de partida do compressor com a bobina aberta.",
          solution: "Troca do relé de partida 220 V e teste do ciclo completo.",
          items: [%w[SRV-DIAG 1], [RELAY, "1"], %w[SRV-HORA 1]], materials: [[RELAY, "1"]] }
      ].freeze

      # Quotes approved by customers seen only in the history and executed by
      # the team, in this order (HistoryPlan#take_quote). :book is what the
      # rules of RoutineBook count (the order itself names no unit); :install,
      # the unit registered when the installation is done.
      HISTORY_QUOTES = [
        { kind: :quote, customer: "31847592619", location: "Residência", customer_kind: "individual",
          contact: "marcos.pereira@cliente.test", crew: :refrigeration, minutes: 225,
          title: "Instalação de split hi-wall no escritório",
          quote: { lines: [%w[SRV-INST-SPLIT 1]],
                   free: [["Split hi-wall inverter 12.000 BTU/h LG S4-Q12JA31A", "1", "2890.00"],
                          ["Kit de instalação (5 m de tubulação de cobre, cabo PP e suporte)", "1", "420.00"]] },
          diagnosis: "Ponto elétrico dedicado disponível; fachada adequada para a condensadora.",
          solution: "Instalação da evaporadora e da condensadora, vácuo na linha e teste de funcionamento por 30 minutos.",
          materials: [%w[PEC-ISOL-38 3]], book: { kind: :written, customer: "31847592619", equipment: [] },
          install: ["Split hi-wall", "LG", "S4-Q12JA31A", "203KAWR3G502", "Residência", "operational", 0, 12] },
        { kind: :quote, customer: "41936057200191", location: "Unidade Santana", customer_kind: "company",
          contact: "renata@ponteidiomas.test", crew: :refrigeration, minutes: 210,
          title: "Higienização completa das quatro evaporadoras", quote: { lines: [%w[SRV-HIG-EVAP 4], %w[SRV-HORA 1]] },
          diagnosis: "Serpentinas e turbinas das quatro evaporadoras com acúmulo de sujeira e biofilme.",
          solution: "Higienização completa das quatro evaporadoras com bactericida e limpeza das bandejas.",
          book: { kind: :corrective, template: :hygiene, customer: "41936057200191",
                  equipment: %w[4251870C0711 4251870C0725 4251870C0739 4251870A1846] } },
        { kind: :quote, customer: "26401937500130", location: "Loja Guapira", customer_kind: "company",
          contact: "debora@drogariavida.test", crew: :refrigeration, minutes: 210,
          title: "Higienização completa das três evaporadoras", quote: { lines: [%w[SRV-HIG-EVAP 3], %w[SRV-HORA 1]] },
          diagnosis: "Serpentinas e bandejas das três evaporadoras com sujeira acumulada e início de biofilme.",
          solution: "Higienização completa das três evaporadoras com bactericida, limpeza das bandejas e dos drenos.",
          book: { kind: :corrective, template: :hygiene, customer: "26401937500130",
                  equipment: %w[112KAUY8L903 112KAUY8L917 203KAZD2J078] } },
        { kind: :quote, customer: "18374629000167", location: "Loja", customer_kind: "company",
          contact: "sergio@padariaestrela.test", crew: :refrigeration, minutes: 270,
          title: "Troca do compressor da câmara fria de laticínios",
          quote: { lines: [%w[PEC-FILTRO-14 1], %w[PEC-R410A 3], %w[SRV-HORA 5]],
                   free: [["Compressor hermético 1 1/2 HP 220 V", "1", "2380.00"]] },
          diagnosis: "Compressor com enrolamento em curto; filtro secador contaminado.",
          solution: "Troca do compressor e do filtro secador, limpeza do circuito com nitrogênio, vácuo e carga de 3 kg.",
          materials: [%w[PEC-FILTRO-14 1], %w[PEC-R410A 3]],
          book: { kind: :corrective, template: :compressor, customer: "18374629000167", equipment: ["CF300-0719"] } },
        { kind: :quote, customer: "93702461800126", location: "Prédio Centro", customer_kind: "company",
          contact: "andre@hubnorte.test", crew: :refrigeration, minutes: 225,
          title: "Instalação de split hi-wall na sala de reuniões",
          quote: { lines: [%w[SRV-INST-SPLIT 1], %w[SRV-HORA 1]],
                   free: [["Split hi-wall inverter 18.000 BTU/h Samsung WindFree", "1", "3990.00"],
                          ["Kit de instalação (6 m de tubulação de cobre, cabo PP e suporte)", "1", "480.00"]] },
          diagnosis: "Circuito dedicado instalado pelo cliente; laje com acesso para a condensadora.",
          solution: "Instalação da evaporadora e da condensadora, vácuo na linha e teste de funcionamento por 30 minutos.",
          materials: [%w[PEC-ISOL-38 4]], book: { kind: :written, customer: "93702461800126", equipment: [] },
          install: ["Split hi-wall", "Samsung", "AR18BVFAMWK", "0FD5PAEN400118M", "Prédio Centro", "operational", 0, 12] },
        { kind: :quote, customer: "82635174000195", location: "Escritório", customer_kind: "company",
          contact: "luis@andrademoreira.test", crew: :refrigeration, minutes: 210,
          title: "Troca da bomba de dreno e higienização dos cassetes",
          quote: { lines: [%w[PEC-BOMBA-DRENO 1], %w[SRV-HIG-EVAP 2], %w[SRV-HORA 1]] },
          diagnosis: "Bomba de dreno do cassete da sala de reuniões travando; evaporadoras com biofilme.",
          solution: "Troca da bomba de dreno e higienização completa dos dois cassetes; drenos testados.",
          materials: [%w[PEC-BOMBA-DRENO 1]],
          book: { kind: :corrective, template: :pump, customer: "82635174000195", equipment: %w[E009844 E009851] } },
        { kind: :quote, customer: "14038592700120", location: "Unidade Santana", customer_kind: "company",
          contact: "beatriz@diagnosticanorte.test", crew: :refrigeration, minutes: 200,
          title: "Troca do isolamento das linhas dos três equipamentos",
          quote: { lines: [%w[PEC-ISOL-38 18], %w[SRV-HORA 3]] },
          diagnosis: "Isolamento das linhas de sucção ressecado e aberto nos trechos externos dos três equipamentos.",
          solution: "Troca de 18 m de isolamento elastomérico, vedação das emendas e fixação das linhas.",
          materials: [%w[PEC-ISOL-38 18]],
          book: { kind: :corrective, template: :insulation, customer: "14038592700120",
                  equipment: %w[E004102 E004871 E004886] } },
        { kind: :quote, customer: "29057136406", location: "Residência", customer_kind: "individual",
          contact: "luciana.prado@cliente.test", crew: :refrigeration, minutes: 225,
          title: "Instalação de split hi-wall no quarto de hóspedes",
          quote: { lines: [%w[SRV-INST-SPLIT 1]],
                   free: [["Split hi-wall inverter 9.000 BTU/h Samsung WindFree", "1", "2490.00"],
                          ["Kit de instalação (4 m de tubulação de cobre, cabo PP e suporte)", "1", "380.00"]] },
          diagnosis: "Quadro com disjuntor livre para o novo circuito; parede externa adequada para a condensadora.",
          solution: "Instalação da evaporadora e da condensadora, vácuo na linha e teste de funcionamento por 30 minutos.",
          materials: [%w[PEC-ISOL-38 3]], book: { kind: :written, customer: "29057136406", equipment: [] },
          install: ["Split hi-wall", "Samsung", "AR09BVFAMWK", "0FD3PAEN200455R", "Residência", "operational", 0, 12] }
      ].freeze

      # Quotes of the routine history that were not executed: refused by the
      # customer or left to expire (valid for 15 days) (ClimaNorte#offers).
      HISTORY_OFFERS = [
        { key: :q_h_store, at: 0.85, outcome: :rejected, after: 3, customer: "61840239700140", location: "Loja",
          contact: "josecarlos@mercadinhovm.test", channel: "phone",
          title: "Troca da unidade condensadora da câmara fria de carnes", lines: [%w[PEC-R410A 4], %w[SRV-HORA 6]],
          free: [["Unidade condensadora 2 HP 220 V", "1", "6850.00"]],
          note: "O cliente preferiu manter a unidade atual e acompanhar o desempenho até o fim do ano." },
        { key: :q_h_suite, at: 0.6, outcome: :rejected, after: 2, customer: "45720381988", location: "Residência",
          contact: "eduardo.bastos@cliente.test", channel: "whatsapp", title: "Instalação de split hi-wall na suíte",
          lines: [%w[SRV-INST-SPLIT 1]],
          free: [["Split hi-wall inverter 12.000 BTU/h Gree G-Top", "1", "2690.00"],
                 ["Kit de instalação (5 m de tubulação de cobre, cabo PP e suporte)", "1", "420.00"]],
          note: "O cliente fechou a instalação com a construtora responsável pela reforma." },
        { key: :q_h_salon, at: 0.35, outcome: :rejected, after: 4, customer: "73419502800164", location: "Salão",
          contact: "simone@bellaarte.test", channel: "email", title: "Instalação de cortina de ar na entrada do salão",
          lines: [%w[SRV-HORA 3]], free: [["Cortina de ar 90 cm 220 V", "1", "1290.00"]],
          note: "A proprietária decidiu adiar a compra para o início do próximo ano." },
        { key: :q_h_living, at: 0.9, outcome: :expired, customer: "19374028603", location: "Residência",
          title: "Instalação de split hi-wall na sala", lines: [%w[SRV-INST-SPLIT 1]],
          free: [["Split hi-wall inverter 18.000 BTU/h Springer Midea AirVolution", "1", "3390.00"],
                 ["Kit de instalação (6 m de tubulação de cobre, cabo PP e suporte)", "1", "480.00"]] }
      ].freeze

      EVENTS = [
        *CUSTOMERS.map { |data| [:start, "08:30", :register_customer, { data: }] },
        # The customers seen only in the history, registered one after the other.
        *ClimaNortePool::CUSTOMERS.each_with_index.map do |data, index|
          hour, minute = (512 + (index * 3)).divmod(60)
          [:start, format("%<hour>02d:%<minute>02d", hour:, minute:), :register_customer, { data: }]
        end,
        [:start, "09:00", :receive_stock, { by: :bruno, warehouse: CENTRAL, sku: MARKER_RECEIPT[1], quantity: "6",
                                            unit_cost: "53.2000", reason: MARKER_RECEIPT[2] }],

        # Completed last week; the bill is overdue and partially paid.
        [-5, "09:20", :open_order, { by: :carla, key: :c0, customer: RENATO, location: "Residência", priority: "high",
                                     origin: "phone", service_type: CORRECTIVE, equipment: ["4216B27715"],
                                     contact: "renato@cliente.test", equipment_status: "attention",
                                     title: "Split piso-teto desarmando — residência",
                                     problem: "O equipamento desarma o disjuntor poucos minutos depois de ligado." }],
        [-5, "09:40", :schedule, { by: :bruno, order: :c0, on: -5, from: "13:30", to: "15:30", technicians: [:diego] }],
        [-5, "13:00", :travel, { by: :diego, order: :c0 }],
        [-5, "13:35", :start, { by: :diego, order: :c0 }],
        [-5, "15:20", :report, { by: :diego, order: :c0,
                                 diagnosis: "Capacitor de partida estufado e carga de gás abaixo do especificado.",
                                 solution: "Troca do capacitor 35+5 µF, recarga de 1 kg de R410A e teste por 30 minutos." }],
        [-5, "15:25", :consume, { by: :diego, order: :c0, warehouse: CENTRAL, sku: "PEC-CAP-355", quantity: "1" }],
        [-5, "15:26", :consume, { by: :diego, order: :c0, warehouse: CENTRAL, sku: "PEC-R410A", quantity: "1" }],
        [-5, "15:30", :items, { by: :diego, order: :c0, contact: "renato@cliente.test", channel: "in_person",
                                lines: [%w[SRV-DIAG 1], %w[PEC-CAP-355 1], %w[PEC-R410A 1], %w[SRV-HORA 1]] }],
        [-5, "15:40", :finish, { by: :diego, order: :c0, outcome: "Equipamento estável após o teste de funcionamento." }],
        [-5, "17:00", :complete, { by: :bruno, order: :c0 }],
        [-5, "17:20", :bill, { by: :gabriela, order: :c0, key: :c0, due_in: 3 }],
        [-2, "10:00", :pay, { by: :gabriela, receivable: :c0, amount: "200.00", method: "transfer" }],

        # Corrective visit paid on the same day.
        [-4, "09:10", :open_order, { by: :carla, key: :c1, customer: HORIZONTE, location: "Loja Paulista", priority: "high",
                                     origin: "email", service_type: CORRECTIVE, equipment: ["112KAUY9K587"],
                                     contact: "paula@horizonte.test", equipment_status: "attention",
                                     title: "Split hi-wall da recepção sem refrigerar",
                                     problem: "O equipamento liga, mas não refrigera; a recepção passa de 28 °C à tarde." }],
        [-4, "09:40", :schedule, { by: :bruno, order: :c1, on: -4, from: "14:00", to: "16:00", technicians: [:diego] }],
        [-4, "09:45", :reserve, { by: :bruno, order: :c1, warehouse: CENTRAL, sku: "PEC-R410A", quantity: "2.5" }],
        [-4, "13:30", :travel, { by: :diego, order: :c1 }],
        [-4, "14:05", :start, { by: :diego, order: :c1 }],
        [-4, "15:10", :report, { by: :diego, order: :c1,
                                 diagnosis: "Vazamento na conexão da condensadora e carga de gás insuficiente.",
                                 solution: "Vedação da conexão, recarga de 2,5 kg de R410A e troca do capacitor." }],
        [-4, "15:15", :consume, { by: :diego, order: :c1, warehouse: CENTRAL, sku: "PEC-R410A", quantity: "2.5",
                                  from_reservation: true }],
        [-4, "15:16", :consume, { by: :diego, order: :c1, warehouse: VAN, sku: "PEC-CAP-355", quantity: "1" }],
        [-4, "15:20", :items, { by: :bruno, order: :c1, contact: "paula@horizonte.test", channel: "phone",
                                lines: [["SRV-DIAG", "1"], ["PEC-R410A", "2.5"], ["PEC-CAP-355", "1"]] }],
        [-4, "15:50", :finish, { by: :diego, order: :c1, outcome: "Temperatura da recepção normalizada (23 °C)." }],
        [-4, "16:10", :complete, { by: :bruno, order: :c1 }],
        [-4, "16:20", :bill, { by: :gabriela, order: :c1, key: :c1, due_in: 10 }],
        [-4, "18:05", :pay, { by: :gabriela, receivable: :c1, method: "pix" }],

        # Quote approved by the customer and converted; executed by the team.
        [-4, "10:00", :quote, { by: :carla, key: :q_converted, customer: CLINICA, location: "Unidade Moema",
                                title: "Higienização das evaporadoras dos consultórios",
                                lines: [%w[SRV-HIG-EVAP 2], %w[SRV-PREV-SPLIT 2]] }],
        [-4, "10:20", :send_quote, { by: :carla, quote: :q_converted }],
        [-3, "09:15", :decide_quote, { by: :carla, quote: :q_converted, contact: "marina@vidaplena.test", channel: "whatsapp",
                                       note: "Aprovado pela gerente administrativa pelo aplicativo de mensagens." }],
        [-3, "09:30", :convert_quote, { by: :bruno, quote: :q_converted, order: :c2 }],
        [-3, "09:45", :schedule, { by: :bruno, order: :c2, on: -2, from: "13:30", to: "16:30", technicians: %i[diego eduarda],
                                   team: "Equipe Refrigeração" }],
        [-3, "14:00", :receive_stock, { by: :bruno, warehouse: CENTRAL, sku: "PEC-R410A", quantity: "10", unit_cost: "54.10",
                                        reason: "Reposição de gás refrigerante — NF 4587" }],
        [-2, "13:00", :travel, { by: :diego, order: :c2 }],
        [-2, "13:35", :start, { by: :diego, order: :c2 }],
        [-2, "16:00", :report, { by: :eduarda, order: :c2,
                                 diagnosis: "Evaporadoras com acúmulo de sujeira e bandejas de condensado com resíduos.",
                                 solution: "Higienização completa das duas evaporadoras, limpeza das bandejas e bactericida." }],
        [-2, "16:10", :finish, { by: :diego, order: :c2, outcome: "Serviço concluído nos dois consultórios." }],
        [-2, "16:40", :complete, { by: :bruno, order: :c2 }],
        [-2, "16:50", :bill, { by: :gabriela, order: :c2, key: :c2_first, due_in: 7, part: [1, 2] }],
        [-2, "16:51", :bill, { by: :gabriela, order: :c2, key: :c2_second, due_in: 30, part: [2, 2] }],
        [-1, "10:00", :pay, { by: :gabriela, receivable: :c2_first, method: "boleto" }],

        # Patrícia asked to move the bedroom split: Eduarda assessed it and the quote was sent the next day,
        # still waiting for her answer. Titled as the routine relocation assessment (RoutineCatalog::MISC),
        # so the routine history never repeats it for her.
        [-6, "16:10", :open_order, { by: :carla, key: :e_move, customer: PATRICIA, location: "Apartamento", priority: "low",
                                     origin: "whatsapp", service_type: INSTALLATION,
                                     contact: "patricia.nogueira@cliente.test", title: "Avaliação para remanejamento do split",
                                     problem: "A cliente quer levar a evaporadora do quarto para a parede oposta e saber " \
                                              "se a tubulação pode seguir pelo forro." }],
        [-6, "16:25", :schedule, { by: :bruno, order: :e_move, on: -4, from: "10:00", to: "11:00", technicians: [:eduarda] }],
        [-4, "09:30", :travel, { by: :eduarda, order: :e_move }],
        [-4, "10:00", :start, { by: :eduarda, order: :e_move }],
        [-4, "10:40", :report, { by: :eduarda, order: :e_move,
                                 diagnosis: "Trajeto de 4 m viável pelo forro do corredor; o dreno pode seguir pela mesma " \
                                            "prumada e o circuito atual atende o equipamento.",
                                 solution: "Medições registradas para o orçamento do remanejamento." }],
        [-4, "10:45", :items, { by: :eduarda, order: :e_move, contact: "patricia.nogueira@cliente.test", channel: "in_person",
                                lines: [%w[SRV-DIAG 1]] }],
        [-4, "10:50", :finish, { by: :eduarda, order: :e_move, outcome: "Avaliação concluída; a cliente aguarda o orçamento." }],
        [-4, "11:05", :complete, { by: :bruno, order: :e_move }],
        [-4, "11:15", :bill, { by: :gabriela, order: :e_move, key: :e_move, due_in: 0 }],
        [-4, "11:30", :pay, { by: :gabriela, receivable: :e_move, method: "pix" }],
        [-3, "10:40", :quote, { by: :carla, key: :q_move, customer: PATRICIA, location: "Apartamento",
                                title: "Remanejamento do split do quarto", lines: [%w[PEC-ISOL-38 4], %w[SRV-HORA 3]] }],
        [-3, "11:05", :send_quote, { by: :carla, quote: :q_move }],

        # Waiting for the second start relay: one unit is reserved, the other was ordered.
        [-3, "16:30", :open_order, { by: :carla, key: :w1, customer: HORIZONTE, location: "Centro de distribuição",
                                     priority: "high", origin: "email", service_type: CORRECTIVE, equipment: ["CF900-2231"],
                                     contact: "paula@horizonte.test", equipment_status: "attention",
                                     title: "Câmara fria do CD com oscilação de temperatura",
                                     problem: "A temperatura interna oscila entre −12 °C e −4 °C; o alarme disparou " \
                                              "duas vezes durante a madrugada." }],
        [-3, "16:45", :schedule, { by: :bruno, order: :w1, on: -2, from: "08:00", to: "09:30", technicians: [:eduarda] }],
        [-2, "07:20", :travel, { by: :eduarda, order: :w1 }],
        [-2, "08:05", :start, { by: :eduarda, order: :w1 }],
        [-2, "09:00", :report, { by: :eduarda, order: :w1, checklist: false,
                                 diagnosis: "Relés de partida dos dois compressores com contatos desgastados; os " \
                                            "compressores armam e desarmam." }],
        [-2, "09:05", :items, { by: :eduarda, order: :w1, contact: "paula@horizonte.test", channel: "phone",
                                lines: [%w[SRV-DIAG 1], [RELAY, "2"], %w[SRV-HORA 1]] }],
        [-2, "09:10", :reserve, { by: :eduarda, order: :w1, warehouse: CENTRAL, sku: RELAY, quantity: "1" }],
        [-2, "09:20", :finish, { by: :eduarda, order: :w1, needs_return: true,
                                 outcome: "Um relé reservado no almoxarifado; o segundo foi encomendado. Retorno após a " \
                                          "chegada da peça." }],
        [-2, "09:40", :wait_parts, { by: :bruno, order: :w1,
                                     reason: "Segundo relé de partida 220 V encomendado ao fornecedor (previsão de " \
                                             "entrega em dois dias úteis)." }],
        [-2, "09:45", :expense, { by: :eduarda, order: :w1, category: "toll", amount: "18.40",
                                  description: "Pedágio Rod. Anhanguera — ida e volta" }],

        # Maintenance contract of the restaurant; the daily job generated its first preventive visit.
        [-2, "15:00", :contract, { by: :bruno, key: :restaurant, customer: RESTAURANTE,
                                   title: "Manutenção da câmara fria — Matriz",
                                   covers: [PREVENTIVE, CORRECTIVE],
                                   attributes: { monthly_fee: "890.00", monthly_visit_limit: 8, covers_parts: false,
                                                 scope: "Preventiva mensal da câmara fria e até oito atendimentos " \
                                                        "corretivos por mês na Matriz." },
                                   plan: { title: "Câmara fria da Matriz", location: "Matriz", service_type: PREVENTIVE,
                                           equipment: ["CF600-1187"], priority: "low", frequency_unit: "month",
                                           frequency_interval: 1, anchor_in: 2, lead_days: 7 } }],
        [-1, "01:30", :generate, { plan: :restaurant, order: :p1 }],
        [-1, "08:10", :schedule, { by: :bruno, order: :p1, on: 1, from: "13:30", to: "15:30", technicians: [:eduarda] }],

        # Low priority request whose resolution deadline is at risk today.
        [:at_risk, "+0", :open_order, { by: :carla, key: :s2, customer: CLINICA, location: "Unidade Moema", priority: "low",
                                        origin: "email", service_type: CORRECTIVE, equipment: ["E006731"],
                                        contact: "marina@vidaplena.test", equipment_status: "attention",
                                        title: "Revisão do split do consultório 1",
                                        problem: "Baixo rendimento no fim da tarde. A clínica pediu a visita para depois " \
                                                 "da reforma da recepção." }],
        [:at_risk, "+20", :schedule, { by: :bruno, order: :s2, on: 1, from: "08:30", to: "10:00", technicians: [:diego] }],

        # Requests of the last business day.
        [-1, "09:30", :open_order, { by: :carla, key: :f1, customer: PRISMA, location: "Sede", priority: "normal",
                                     origin: "phone", service_type: CORRECTIVE, equipment: ["E009212"],
                                     contact: "helena@prisma.test", equipment_status: "attention",
                                     title: "Cassete da recepção desarmando o disjuntor",
                                     problem: "O disjuntor do cassete da recepção desarma logo depois da partida." }],
        [-1, "09:50", :schedule, { by: :bruno, order: :f1, on: :today, from: "10:00", to: "11:30", technicians: [:fabio] }],
        [-1, "10:30", :open_order, { by: :carla, key: :n1, customer: PRISMA, location: "Sede", priority: "low",
                                     origin: "email", service_type: CORRECTIVE, contact: "helena@prisma.test",
                                     title: "Revisão do quadro elétrico da climatização",
                                     problem: "Avaliação dos disjuntores e do aterramento dos equipamentos depois das " \
                                              "quedas de energia do último mês." }],
        [-1, "10:45", :schedule, { by: :bruno, order: :n1, on: 1, from: "09:00", to: "10:30", technicians: [:fabio] }],
        [-1, "11:00", :open_order, { by: :carla, key: :s1, customer: CLINICA, location: "Unidade Moema", priority: "normal",
                                     origin: "whatsapp", service_type: CORRECTIVE, equipment: ["E006748"],
                                     contact: "marina@vidaplena.test", equipment_status: "attention",
                                     title: "Split do consultório 2 pingando",
                                     problem: "Água escorrendo pela parede abaixo da evaporadora desde ontem." }],
        [-1, "11:30", :schedule, { by: :bruno, order: :s1, on: :today, from: "08:00", to: "09:30", technicians: [:eduarda] }],
        [-1, "13:00", :open_order, { by: :carla, key: :tv1, customer: HORIZONTE, location: "Loja Paulista",
                                     priority: "normal", origin: "phone", service_type: CORRECTIVE,
                                     equipment: ["4219C31207"], contact: "paula@horizonte.test", equipment_status: "attention",
                                     title: "Cassete do salão de vendas com ruído metálico",
                                     problem: "Ruído metálico na unidade interna, mais forte no fim da tarde, sobre a " \
                                              "área dos caixas." }],
        [-1, "13:20", :schedule, { by: :bruno, order: :tv1, on: :today, from: "15:30", to: "17:30",
                                   technicians: %i[eduarda fabio] }],
        # Sent two days ago; Paula asked for one more evaporator and the drain pump, so version 2 was sent yesterday.
        [-2, "11:00", :quote, { by: :carla, key: :q_sent, customer: HORIZONTE, location: "Loja Paulista",
                                title: "Higienização completa das evaporadoras da Loja Paulista",
                                lines: [%w[SRV-HIG-EVAP 3], %w[SRV-HORA 2]] }],
        [-2, "11:20", :send_quote, { by: :carla, quote: :q_sent }],
        [-1, "10:10", :revise_quote, { by: :carla, quote: :q_sent, lines: [%w[SRV-HIG-EVAP 1], %w[PEC-BOMBA-DRENO 1]],
                                       notes: "Versão 2 a pedido de Paula Reis (facilities): inclui a evaporadora do " \
                                              "depósito e a troca preventiva da bomba de dreno do cassete do salão." }],
        [-1, "10:25", :send_quote, { by: :carla, quote: :q_sent }],

        # Approved by the academy's manager in the portal last evening, not converted yet.
        [-2, "15:30", :quote, { by: :carla, key: :q_approved, customer: ACADEMIA, location: "Unidade Vila Mariana",
                                title: "Troca do motor ventilador e do contator do split da sala de spinning",
                                lines: [%w[SRV-DIAG 1], %w[PEC-MOTOR-VENT 1], %w[PEC-CONTATOR-32 1], %w[SRV-HORA 3]] }],
        [-2, "15:50", :send_quote, { by: :carla, quote: :q_approved }],
        [-1, "18:20", :decide_quote, { quote: :q_approved, contact: "tiago@movimento.test", channel: "portal" }],
        [-1, "15:00", :open_order, { by: :carla, key: :c3, customer: RESTAURANTE, location: "Matriz", priority: "normal",
                                     origin: "whatsapp", service_type: CORRECTIVE, equipment: ["4216B42218"],
                                     contact: "rafael@saborserra.test", equipment_status: "attention",
                                     title: "Split do salão desarmando no horário de pico",
                                     problem: "O equipamento desarma no horário do almoço, com o salão cheio." }],
        [-1, "15:20", :schedule, { by: :bruno, order: :c3, on: :today, from: "08:00", to: "09:30", technicians: [:diego] }],
        # Installations are not covered by the store's contract: the one "não coberto" order.
        [-1, "16:30", :open_order, { by: :carla, key: :o2, customer: HORIZONTE, location: "Loja Paulista", priority: "low",
                                     origin: "email", service_type: INSTALLATION, contact: "paula@horizonte.test",
                                     title: "Avaliação para instalação de split no depósito",
                                     problem: "Visita técnica para dimensionar um equipamento para o depósito dos " \
                                              "fundos (cerca de 20 m²)." }],
        [-1, "17:00", :open_order, { by: :carla, key: :ip1, customer: ACADEMIA, location: "Unidade Vila Mariana",
                                     priority: "normal", origin: "preventive", service_type: PREVENTIVE,
                                     equipment: %w[112KAUY9M204 112KAUY9M211 4251880E0127], contact: "tiago@movimento.test",
                                     title: "Preventiva geral dos splits antes do verão",
                                     problem: "Revisão dos três equipamentos da unidade antes do aumento de alunos no " \
                                              "verão." }],
        [-1, "17:15", :schedule, { by: :bruno, order: :ip1, on: :today, from: "13:30", to: "16:30", technicians: [:diego] }],
        [-1, "17:20", :reserve, { by: :bruno, order: :ip1, warehouse: CENTRAL, sku: "PEC-R410A", quantity: "1.5" }],
        [-1, "17:25", :items, { by: :bruno, order: :ip1, contact: "tiago@movimento.test", channel: "phone",
                                lines: [%w[SRV-PREV-SPLIT 3]] }],
        [-1, "17:40", :quote, { by: :carla, key: :q_draft, customer: RENATO, location: "Residência",
                                title: "Troca da placa eletrônica do split piso-teto", lines: [%w[SRV-HORA 2]],
                                free: [["Placa eletrônica da evaporadora Carrier 42XQV036515LC", "1", "780.00"]] }],

        # Opened by Renato in the portal after hours for his bedroom split ("equipamento parado": high
        # priority; the unit is marked "Parado"), waiting for triage: its first response is due mid-morning
        # (business hours). The bedroom split was not part of last week's repair.
        [-1, "17:50", :portal_request, { key: :o1, contact: "renato@cliente.test", location: "Residência", urgency: "high",
                                         equipment: "E007412", equipment_status: "inoperative",
                                         title: "Split do quarto parado — residência",
                                         problem: "O equipamento parou depois de uma queda de energia no fim da tarde e " \
                                                  "não liga nem pelo controle nem pelo botão da evaporadora." }],

        # Today: three visits in the morning, Renato's portal request triaged (as a corrective visit) and
        # scheduled mid-morning (after its first response deadline) and solved before lunch (well within its
        # resolution deadline), Diego in the afternoon, Eduarda and Fábio together at the end of the day, a new
        # request at 14:10 scheduled for the next business day; the clinic's low-priority order, at risk all
        # day, waits for the customer from 16:20, so the day ends without any deadline running out.
        # Applied as their time comes (Living): a Pix at 09:50, Renato settles the overdue bill and the repair in
        # the afternoon, the installation assessment is scheduled, the second relay arrives late in the morning
        # and is reserved, and at the end of the day the return visit of the cold room is scheduled for the next
        # business day (the order leaves "Aguardando peças" with its deadline after that visit).
        [:today, "07:30", :travel, { by: :diego, order: :c3 }],
        [:today, "07:30", :travel, { by: :eduarda, order: :s1 }],
        [:today, "08:00", :start, { by: :diego, order: :c3 }],
        [:today, "08:05", :start, { by: :eduarda, order: :s1 }],
        [:today, "09:00", :report, { by: :eduarda, order: :s1,
                                     diagnosis: "Mangueira de dreno desconectada atrás da evaporadora.",
                                     solution: "Mangueira reconectada e fixada; teste de escoamento com 1 litro de água." }],
        [:today, "09:05", :items, { by: :eduarda, order: :s1, contact: "marina@vidaplena.test", channel: "in_person",
                                    lines: [%w[SRV-DIAG 1], %w[SRV-HORA 1]] }],
        [:today, "09:10", :report, { by: :diego, order: :c3,
                                     diagnosis: "Capacitor do ventilador da condensadora abaixo da capacitância nominal.",
                                     solution: "Troca do capacitor e medição da corrente; equipamento estável após " \
                                               "40 minutos." }],
        [:today, "09:12", :consume, { by: :diego, order: :c3, warehouse: VAN, sku: "PEC-CAP-355", quantity: "1" }],
        [:today, "09:15", :items, { by: :diego, order: :c3, contact: "rafael@saborserra.test", channel: "in_person",
                                    lines: [%w[SRV-DIAG 1], %w[PEC-CAP-355 1], %w[SRV-HORA 1]] }],
        [:today, "09:20", :finish, { by: :eduarda, order: :s1, outcome: "Sem gotejamento após o teste." }],
        [:today, "09:30", :finish, { by: :diego, order: :c3, outcome: "Equipamento estável; cliente acompanhou o teste." }],
        [:today, "09:30", :travel, { by: :fabio, order: :f1 }],
        [:today, "09:40", :complete, { by: :bruno, order: :c3 }],
        [:today, "09:45", :bill, { by: :gabriela, order: :c3, key: :c3, due_in: 0 }],
        [:today, "09:45", :complete, { by: :bruno, order: :s1 }],
        [:today, "09:50", :pay, { by: :gabriela, receivable: :c3, method: "pix" }],
        [:today, "09:55", :bill, { by: :gabriela, order: :s1, key: :s1, due_in: 10 }],
        [:today, "10:05", :start, { by: :fabio, order: :f1 }],
        [:today, "11:00", :report, { by: :fabio, order: :f1,
                                     diagnosis: "Contator do compressor com contatos carbonizados e disjuntor de 16 A " \
                                                "abaixo da corrente de partida.",
                                     solution: "Troca do contator e do disjuntor por um de 20 A, curva C; partida medida." }],
        [:today, "11:02", :consume, { by: :fabio, order: :f1, warehouse: CENTRAL, sku: "PEC-CONTATOR-32", quantity: "1" }],
        [:today, "11:03", :consume, { by: :fabio, order: :f1, warehouse: CENTRAL, sku: "PEC-DISJ-20", quantity: "1" }],
        [:today, "11:05", :items, { by: :fabio, order: :f1, contact: "helena@prisma.test", channel: "in_person",
                                    lines: [%w[SRV-DIAG 1], %w[PEC-CONTATOR-32 1], %w[PEC-DISJ-20 1], %w[SRV-HORA 1]] }],
        [:today, "11:20", :finish, { by: :fabio, order: :f1, outcome: "Equipamento operando sem desarmes." }],
        [:today, "11:40", :complete, { by: :bruno, order: :f1 }],
        [:today, "11:50", :bill, { by: :gabriela, order: :f1, key: :f1, due_in: 15 }],
        [:today, "10:15", :triage, { by: :bruno, order: :o1, service_type: CORRECTIVE,
                                     reason: "Triagem: atendimento corretivo no mesmo dia (equipamento parado)." }],
        [:today, "10:30", :schedule, { by: :bruno, order: :o1, on: :today, from: "11:00", to: "12:00", technicians: [:diego] }],
        [:today, "10:35", :travel, { by: :diego, order: :o1 }],
        [:today, "11:05", :start, { by: :diego, order: :o1 }],
        [:today, "11:35", :report, { by: :diego, order: :o1,
                                     diagnosis: "Placa eletrônica travada pela proteção após a queda de energia; sem " \
                                                "componentes danificados.",
                                     solution: "Reinicialização da placa, reaperto dos conectores e teste de partida; " \
                                               "cliente orientado a usar protetor contra surtos." }],
        [:today, "11:40", :items, { by: :diego, order: :o1, contact: "renato@cliente.test", channel: "in_person",
                                    lines: [%w[SRV-DIAG 1]] }],
        [:today, "11:50", :finish, { by: :diego, order: :o1, outcome: "Equipamento funcionando; testado por 20 minutos." }],
        [:today, "12:05", :complete, { by: :bruno, order: :o1 }],
        [:today, "12:15", :bill, { by: :gabriela, order: :o1, key: :o1, due_in: 0 }],
        [:today, "13:00", :travel, { by: :diego, order: :ip1 }],
        [:today, "13:40", :start, { by: :diego, order: :ip1 }],
        [:today, "13:55", :answer, { by: :diego, order: :ip1, label: "Pressão de sucção (psi)", response: "118" }],
        [:today, "14:20", :pay, { by: :gabriela, receivable: :c0, method: "pix" }],
        [:today, "14:22", :pay, { by: :gabriela, receivable: :o1, method: "pix" }],
        [:today, "14:40", :schedule, { by: :bruno, order: :o2, on: 1, from: "14:00", to: "15:30", technicians: [:fabio] }],
        [:today, "15:05", :travel, { by: :eduarda, order: :tv1 }],
        [:today, "15:10", :report, { by: :diego, order: :ip1, checklist: false,
                                     diagnosis: "Filtros saturados nos três equipamentos; dreno do split da sala de " \
                                                "spinning com escoamento lento." }],
        [:today, "15:40", :start, { by: :eduarda, order: :tv1 }],
        [:today, "16:10", :report, { by: :diego, order: :ip1, notes: "Filtros trocados nos três equipamentos.",
                                     diagnosis: "Filtros saturados nos três equipamentos; dreno do split da sala de " \
                                                "spinning com escoamento lento.",
                                     solution: "Troca dos filtros, limpeza das serpentinas, desobstrução do dreno e " \
                                               "complemento de 1,5 kg de R410A no split da sala de spinning." }],
        [:today, "16:15", :consume, { by: :diego, order: :ip1, warehouse: CENTRAL, sku: "PEC-R410A", quantity: "1.5",
                                      from_reservation: true }],
        [:today, "16:25", :finish, { by: :diego, order: :ip1, outcome: "Três equipamentos revisados e testados." }],
        [:today, "16:45", :complete, { by: :bruno, order: :ip1 }],
        [:today, "16:55", :bill, { by: :gabriela, order: :ip1, key: :ip1, due_in: 10 }],
        [:today, "16:50", :report, { by: :fabio, order: :tv1,
                                     diagnosis: "Rolamento do motor da turbina com folga e suporte do motor trincado.",
                                     solution: "Troca do rolamento, novo suporte do motor e balanceamento da turbina." }],
        [:today, "17:00", :items, { by: :eduarda, order: :tv1, contact: "paula@horizonte.test", channel: "phone",
                                    lines: [%w[SRV-DIAG 1], %w[SRV-HORA 2]] }],
        [:today, "17:15", :finish, { by: :eduarda, order: :tv1, outcome: "Ruído eliminado; cassete testado por 20 minutos." }],
        [:today, "17:35", :complete, { by: :bruno, order: :tv1 }],
        [:today, "17:45", :bill, { by: :gabriela, order: :tv1, key: :tv1, due_in: 10 }],
        # The clinic asks to wait for the end of the reception renovation: the order of the consultório 1 waits
        # for the customer (its resolution deadline, at risk since the morning, is paused before it runs out)
        # and its visit of the next business day is called off; it is scheduled again when the clinic calls.
        [:today, "16:20", :wait_customer, { by: :carla, order: :s2,
                                            reason: "A clínica pediu para aguardar a conclusão da reforma da recepção; " \
                                                    "a visita será reagendada quando o ambiente for liberado." }],
        [:today, "16:25", :cancel_visit, { by: :bruno, order: :s2,
                                           reason: "Cancelada a pedido da clínica até a conclusão da reforma da " \
                                                   "recepção." }],
        # A request that arrives during the day: the school's message is registered by Carla and Bruno
        # schedules Diego for the next business day (both deadlines well ahead at the end of the day).
        [:today, "14:10", :open_order, { by: :carla, key: :n2, customer: PEQUENO_SABER, location: "Unidade Mandaqui",
                                         priority: "normal", origin: "whatsapp", service_type: CORRECTIVE,
                                         equipment: ["203KAPX4B226"], contact: "cristina@pequenosaber.test",
                                         equipment_status: "attention", title: "Split da sala do maternal pingando",
                                         problem: "Água pingando sobre o tapete da sala desde o fim da manhã; as crianças " \
                                                  "foram levadas para outra sala." }],
        [:today, "14:30", :schedule, { by: :bruno, order: :n2, on: 1, from: "14:00", to: "15:30", technicians: [:diego] }],
        [:today, "11:10", :receive_stock, { by: :bruno, warehouse: CENTRAL, sku: RELAY, quantity: "3", unit_cost: "66.9000",
                                            reason: "Relés de partida 220 V — NF 4611" }],
        [:today, "11:15", :reserve, { by: :bruno, order: :w1, warehouse: CENTRAL, sku: RELAY, quantity: "1" }],
        # Scheduled at the end of the day, so the deadline resumed with it falls after the return visit.
        [:today, "17:40", :schedule, { by: :bruno, order: :w1, on: 1, from: "10:30", to: "12:00", technicians: [:eduarda] }]
      ].freeze

      private

      # Routine history (History) plus the quotes that depend on the length of
      # the story.
      def extra_events
        span = history_days
        [*super, *refused_quote(-(span / 2)), *(span >= 15 ? [*expired_quote(-(span - 2)), *offers] : [])]
      end

      # The quotes of HISTORY_OFFERS, sent at their share of the story (`at`)
      # and decided `after` business days later, or left unanswered (:expired).
      def offers
        HISTORY_OFFERS.flat_map do |offer|
          day = -(history_days * offer[:at]).round
          data = { by: :carla, key: offer[:key], **offer.slice(:customer, :location, :title, :lines, :free) }
          sent = [[day, "10:40", :quote, data], [day, "11:05", :send_quote, { by: :carla, quote: offer[:key] }]]
          next sent unless offer[:outcome] == :rejected

          [*sent, [day + offer[:after], "15:10", :decide_quote,
                   { by: :carla, quote: offer[:key], decision: "rejected", **offer.slice(:contact, :channel, :note) }]]
        end
      end

      def refused_quote(day)
        [[day, "10:00", :quote, { by: :carla, key: :q_refused, customer: ACADEMIA, location: "Unidade Vila Mariana",
                                  title: "Substituição do split da sala de spinning", lines: [%w[SRV-HORA 6]],
                                  free: [["Split piso-teto inverter 60.000 BTU/h Carrier 42XQV060515LC", "1", "14900.00"]] }],
         [day, "10:30", :send_quote, { by: :carla, quote: :q_refused }],
         [day + 2, "11:00", :decide_quote, { by: :carla, quote: :q_refused, decision: "rejected", channel: "email",
                                             contact: "tiago@movimento.test",
                                             note: "A academia decidiu adiar a substituição para o próximo semestre, " \
                                                   "por limite de orçamento." }]]
      end

      def expired_quote(day)
        [[day, "14:00", :quote, { by: :carla, key: :q_expired, customer: PRISMA, location: "Sede",
                                  title: "Instalação de split na sala de treinamento", lines: [%w[SRV-HORA 4]],
                                  free: [["Split hi-wall inverter 18.000 BTU/h Daikin FTKP18Q5VL", "1", "4350.00"]] }],
         [day, "14:30", :send_quote, { by: :carla, quote: :q_expired }]]
      end

      def prepare
        policy = SlaPolicy.find_by(priority: "low")
        @risk_instant = policy ? at_risk_request(policy) : zone.local(@today.year, @today.month, @today.day) - 5.days
      end

      # Request instant whose resolution clock enters the warning window one
      # minute before the last business period ends before today, so it stays
      # "at risk" through most of today (and over weekends and holidays).
      def at_risk_request(policy)
        calendar = story_calendar(business_hours_only: policy.business_hours_only)
        limit = zone.local(@today.year, @today.month, @today.day)
        wanted = (policy.resolution_minutes * 60 * policy.warning_percent / 100) + 60
        earliest = limit - 90.days
        latest = limit
        while latest - earliest > 60
          middle = earliest + ((latest - earliest) / 2)
          calendar.elapsed(middle, limit) >= wanted ? earliest = middle : latest = middle
        end
        earliest.change(sec: 0)
      end
    end
  end
end
