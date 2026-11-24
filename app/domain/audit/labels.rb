# frozen_string_literal: true

module Audit
  # Readable pt-BR names for audit actions ("work_order.completed" becomes
  # "Ordem de serviço · concluída") and for the fields of their changesets.
  #
  # Every action recorded through AuditEvent.record! must be listed in
  # ACTIONS (spec/lib/audit/labels_coverage_spec.rb scans app/ for them). Keys
  # that are not listed, such as events written by an older release, fall
  # back to a humanized version of the key and never raise.
  class Labels
    SEPARATOR = " · "

    # area key => [area label, { action suffix => what happened }]
    ACTIONS = {
      "absence" => ["Ausência", { "registered" => "registrada", "released" => "liberada" }],
      "api_credential" => ["Credencial de API", { "created" => "criada", "revoked" => "revogada" }],
      "catalog_item" => ["Catálogo", { "created" => "item criado", "updated" => "item alterado" }],
      "contract" => ["Contrato", {
        "created" => "criado", "revised" => "revisado", "active" => "ativado", "suspended" => "suspenso",
        "ended" => "encerrado"
      }],
      "customer" => ["Cliente", {
        "created" => "cadastrado", "updated" => "alterado", "archived" => "arquivado", "restored" => "restaurado"
      }],
      "customer_contact" => ["Contato do cliente", {
        "created" => "cadastrado", "updated" => "alterado", "archived" => "arquivado"
      }],
      "equipment" => ["Equipamento", {
        "registered" => "cadastrado", "updated" => "alterado", "removed" => "excluído", "archived" => "arquivado",
        "restored" => "restaurado", "relocated" => "realocado", "ownership_transferred" => "transferido de cliente",
        "status_changed" => "estado operacional alterado"
      }],
      "expense" => ["Despesa", { "recorded" => "registrada" }],
      "fiscal_setting" => ["Configuração fiscal", { "updated" => "alterada" }],
      "holiday" => ["Feriado", { "created" => "cadastrado", "removed" => "removido" }],
      "invitation" => ["Convite", { "issued" => "enviado", "accepted" => "aceito", "revoked" => "revogado" }],
      "maintenance_plan" => ["Plano de manutenção", { "created" => "criado", "updated" => "alterado" }],
      "membership" => ["Membro da equipe", {
        "updated" => "alterado", "deactivated" => "desativado", "reactivated" => "reativado"
      }],
      "organization" => ["Organização", { "created" => "criada", "updated" => "configurações alteradas" }],
      "outbox" => ["Fila de eventos", { "reprocessed" => "evento reprocessado" }],
      "payment_integration" => ["Integração de pagamentos", {
        "updated" => "alterada", "webhook_token_rotated" => "token de notificações renovado"
      }],
      "payment_refund" => ["Estorno", {
        "accepted" => "aceito pelo provedor", "failed" => "recusado pelo provedor", "unknown" => "em verificação",
        "confirm" => "confirmado manualmente", "retry" => "reenviado ao provedor"
      }],
      "quote" => ["Orçamento", {
        "created" => "criado", "sent" => "enviado", "approved" => "aprovado", "rejected" => "recusado",
        "canceled" => "cancelado"
      }],
      "receivable" => ["Recebível", {
        "issued" => "emitido", "canceled" => "cancelado", "discount_granted" => "desconto concedido",
        "payment_registered" => "pagamento registrado", "refunded" => "pagamento estornado"
      }],
      "report" => ["Relatório", { "exported" => "exportado" }],
      "service_invoice" => ["Nota fiscal de serviço", {
        "requested" => "emissão solicitada", "cancel_requested" => "cancelamento solicitado",
        "pending" => "aguardando envio", "scheduled" => "em processamento na prefeitura", "authorized" => "autorizada",
        "unknown" => "em verificação", "error" => "rejeitada", "canceling" => "cancelamento em andamento",
        "canceled" => "cancelada"
      }],
      "service_location" => ["Local de atendimento", {
        "created" => "cadastrado", "updated" => "alterado", "archived" => "arquivado"
      }],
      "sla" => ["Prazos de atendimento", { "configured" => "configurados" }],
      "stock" => ["Estoque", {
        "received" => "entrada registrada", "adjusted" => "ajuste registrado", "minimum_changed" => "mínimo alterado"
      }],
      "subscription" => ["Assinatura", {
        "activated" => "ativada", "changed" => "alterada", "past_due" => "pagamento pendente"
      }],
      "subscription_invoice" => ["Fatura da assinatura", { "paid" => "paga" }],
      "technician" => ["Técnico", { "profile_updated" => "perfil alterado" }],
      "visit" => ["Visita", {
        "scheduled" => "agendada", "rescheduled" => "reagendada", "canceled" => "cancelada",
        "no_show" => "cliente ausente"
      }],
      "warehouse" => ["Depósito", { "created" => "criado", "updated" => "alterado" }],
      "webhook_delivery" => ["Entrega de webhook", { "redelivered" => "reenvio solicitado" }],
      "webhook_endpoint" => ["Webhook", { "created" => "criado", "enabled" => "ativado", "disabled" => "desativado" }],
      "work_order" => ["Ordem de serviço", {
        "created" => "criada", "assigned" => "técnico atribuído", "unassigned" => "técnico removido",
        "completed" => "concluída", "reopened" => "reaberta", "canceled" => "cancelada",
        "item_added" => "item adicional incluído", "item_authorized" => "item adicional autorizado",
        "item_rejected" => "item adicional recusado", "evidence_added" => "evidência anexada",
        "evidence_removed" => "evidência removida"
      }]
    }.freeze

    # Actions whose changeset comes from saved_changes: { field => [before, after] }.
    DIFF_ACTIONS = %w[
      catalog_item.updated customer.updated customer_contact.updated equipment.updated fiscal_setting.updated
      maintenance_plan.created maintenance_plan.updated membership.updated organization.updated
      service_location.updated warehouse.updated
    ].freeze

    # Label for changesets written as { from:, to: } (one line "before → after").
    FROM_TO = {
      "contract" => "Situação", "equipment.status_changed" => "Estado operacional",
      "report.exported" => "Período", "stock.minimum_changed" => "Estoque mínimo"
    }.freeze

    # Generic field names, used when the record type has no translated attribute.
    FIELDS = {
      "access_instructions" => "Instruções de acesso", "active" => "Ativo", "amount" => "Valor",
      "anchor_date" => "Data base", "api_key" => "Chave de API", "archived_at" => "Arquivado em",
      "asset_tag" => "Patrimônio", "auto_issue_on_payment" => "Emitir ao receber pagamento",
      "byte_size" => "Tamanho", "can_approve" => "Pode aprovar", "can_follow" => "Acompanha atendimentos",
      "capacity" => "Capacidade", "category" => "Categoria", "channel" => "Canal", "city" => "Cidade",
      "complement" => "Complemento", "contact_id" => "Contato", "content_type" => "Tipo de arquivo",
      "custodian_membership_id" => "Responsável", "customer_id" => "Cliente", "deactivated_at" => "Desativado em",
      "default_description" => "Descrição padrão", "delta" => "Quantidade ajustada", "description" => "Descrição",
      "district" => "Bairro", "document" => "Documento", "due_on" => "Vencimento", "email" => "E-mail",
      "equipment_type" => "Tipo", "error" => "Erro", "estimated_minutes" => "Duração estimada",
      "event_type" => "Tipo de evento", "events" => "Eventos", "external_id" => "Identificador no provedor",
      "filename" => "Arquivo", "from" => "De", "to" => "Para", "frequency_interval" => "Intervalo",
      "frequency_unit" => "Unidade de frequência",
      "installed_on" => "Data de instalação", "instructions" => "Instruções", "intervals" => "Faixas de horário",
      "iss_rate" => "Alíquota de ISS", "item" => "Item", "job_title" => "Cargo", "kind" => "Tipo",
      "last_error" => "Erro", "lead_days" => "Antecedência", "legal_name" => "Razão social",
      "location_id" => "Local", "manufacturer" => "Fabricante", "membership_id" => "Técnico",
      "method" => "Forma de pagamento", "mfa_required_for_privileged" => "Verificação em duas etapas obrigatória",
      "model" => "Modelo", "modules" => "Módulos", "monthly_amount" => "Valor mensal", "name" => "Nome",
      "note" => "Observação", "notes" => "Observações", "number" => "Número",
      "municipal_service_code" => "Código do serviço municipal",
      "municipal_service_name" => "Serviço municipal", "operational_status" => "Estado operacional",
      "period_start" => "Início do período", "phone" => "Telefone", "plan" => "Plano",
      "policies" => "Políticas de prazo", "portal_enabled" => "Acesso ao portal", "position" => "Cargo",
      "postal_code" => "CEP", "priority" => "Prioridade", "provider" => "Provedor", "quantity" => "Quantidade",
      "quote" => "Orçamento", "reason" => "Motivo", "report" => "Relatório", "report_version" => "Versão do relatório",
      "retain_iss" => "Reter ISS", "role" => "Perfil", "schedule_mode" => "Modo de agendamento",
      "scopes" => "Permissões", "seats" => "Licenças", "segment" => "Segmento", "serial_number" => "Número de série",
      "service_location_id" => "Local de atendimento", "shifts" => "Turnos", "skills" => "Habilidades",
      "sku" => "Código", "starts_at" => "Início", "state" => "UF", "status" => "Situação", "street" => "Logradouro",
      "technicians" => "Técnicos", "time_zone" => "Fuso horário", "title" => "Título", "total" => "Total",
      "tracks_inventory" => "Controla estoque", "trade_name" => "Nome fantasia",
      "travel_buffer_minutes" => "Deslocamento padrão", "unit" => "Unidade", "unit_cost" => "Custo unitário",
      "unit_price" => "Preço", "url" => "Endereço", "user_id" => "Pessoa", "version" => "Versão",
      "warehouse" => "Depósito", "warranty_notes" => "Observações da garantia", "warranty_until" => "Garantia até"
    }.freeze

    # Values written by the application that are not data (Audit::Redactor masks, change markers).
    CHANGED_MARKER = Audit::Redactor::CHANGED_MARKER

    # Plumbing that says nothing to an auditor.
    TECHNICAL_FIELDS = %w[
      id organization_id created_at updated_at lock_version anchor_sequence last_sequence
      onboarding_completed_at request_id ip_address
    ].freeze

    class << self
      # "Ordem de serviço · concluída"; unknown keys are humanized ("Foo bar · baz").
      def action(key)
        area_key, suffix = split(key)
        return "—" if area_key.empty?
        return humanize(area_key) if suffix.empty?

        [area(area_key), verb(area_key, suffix)].join(SEPARATOR)
      end

      def area(key)
        area_key, = split(key)
        ACTIONS.dig(area_key, 0) || humanize(area_key)
      end

      def known?(key)
        area_key, suffix = split(key)
        ACTIONS.dig(area_key, 1)&.key?(suffix) || false
      end

      # [[area label, [[action label, key], ...]], ...] ordered by area, for grouped selects.
      def grouped(keys)
        keys.map(&:to_s).uniq.group_by { |key| area(key) }.sort_by { |label, _| collation_key(label) }
          .map { |label, group| [label, group.map { |key| [action(key), key] }.sort_by { |text, _| collation_key(text) }] }
      end

      # pt-BR ordering: accents do not move a label ("Orçamento" before "Ordem").
      def collation_key(text) = text.unicode_normalize(:nfd).gsub(/\p{Mn}/, "").downcase

      def diff?(key) = DIFF_ACTIONS.include?(key.to_s)

      def from_to_label(key)
        area_key, = split(key)
        FROM_TO[key.to_s] || FROM_TO[area_key] || "Valor"
      end

      def field(name) = FIELDS[name.to_s] || humanize(name)

      # Fields never shown: plumbing, unresolvable foreign keys and anything
      # whose name looks like a credential (same rule as Audit::Redactor).
      def hidden?(name, references: [])
        name = name.to_s
        return true if TECHNICAL_FIELDS.include?(name)
        return true if name.end_with?("_id") && references.exclude?(name)

        sensitive?(name)
      end

      def sensitive?(name) = Redactor::SENSITIVE_KEY.match?(name.to_s)

      private

      def split(key)
        area_key, suffix = key.to_s.strip.split(".", 2)
        [area_key.to_s, suffix.to_s]
      end

      def verb(area_key, suffix)
        ACTIONS.dig(area_key, 1, suffix) || humanize(suffix).downcase
      end

      def humanize(value) = value.to_s.tr(".", " ").humanize
    end
  end
end
