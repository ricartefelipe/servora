Rails.application.routes.draw do
  get "up" => "health#live", as: :liveness
  get "ready" => "health#ready", as: :readiness
  get "metrics" => "metrics#show", as: :metrics

  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  %w[403 404 406 422 429 500].each do |code|
    match code, to: "errors#show", via: :all, code: code
  end

  scope path_names: { new: "nova", edit: "editar" } do
    devise_for :users,
      path: "conta",
      format: false,
      path_names: {
        sign_in: "entrar", sign_out: "sair", sign_up: "criar", registration: "cadastro",
        password: "senha", confirmation: "confirmacao", unlock: "desbloqueio", edit: "editar", new: "nova",
        cancel: "cancelar"
      },
      controllers: {
        registrations: "users/registrations", confirmations: "users/confirmations",
        unlocks: "users/unlocks", passwords: "users/passwords"
      },
      skip: :sessions
  end

  # The sign-in form is the front door of the application: "/" renders it for
  # visitors and sends authenticated users to their organizations.
  authenticated :user do
    root to: redirect("/organizacoes", status: 302), as: :authenticated_root
  end

  devise_scope :user do
    root "users/sessions#new"
    get "/", to: "users/sessions#new", as: :new_user_session
    # Former sign-in address, kept as a permanent redirect for bookmarks and old e-mails.
    get "conta/entrar", to: redirect("/", status: 301), as: nil
    post "conta/entrar", to: "users/sessions#create", as: :user_session, format: false
    delete "conta/sair", to: "users/sessions#destroy", as: :destroy_user_session, format: false
    get "conta/verificacao", to: "users/sessions#two_factor", as: :user_two_factor_challenge
    post "conta/verificacao", to: "users/sessions#verify_two_factor", as: nil
    post "conta/confirmacao/confirmar", to: "users/confirmations#confirm", as: :confirm_user_confirmation
    post "conta/desbloqueio/confirmar", to: "users/unlocks#confirm", as: :confirm_user_unlock
  end

  scope path_names: { new: "novo", edit: "editar" } do
    # Account level (no organization context)
    resources :organizations, path: "organizacoes", only: %i[index new create] do
      post :select, on: :member, path: "selecionar"
    end
    get "convites/:token", to: "invitation_acceptances#show", as: :invitation
    post "convites/:token", to: "invitation_acceptances#create"

    namespace :account, path: "conta" do
      resource :security, only: :show, path: "seguranca", controller: "security"
      resources :sessions, only: :destroy, path: "sessoes" do
        delete :others, on: :collection, path: "outras"
      end
      resource :two_factor, only: %i[new create destroy], path: "verificacao-em-duas-etapas", path_names: { new: "ativar" }
    end

    # Organization level
    get "painel", to: "dashboards#show", as: :dashboard
    get "busca", to: "searches#show", as: :search
    resources :members, path: "equipe", only: %i[index edit update] do
      member do
        patch :deactivate, path: "desativar"
        patch :reactivate, path: "reativar"
      end
    end
    resources :invitations, path: "equipe/convites", only: %i[create destroy], as: :team_invitations
    resource :settings, path: "configuracoes", only: %i[edit update] do
      patch :complete_onboarding, path: "concluir-primeiros-passos"
    end
    resources :customers, path: "clientes", except: :destroy do
      member do
        patch :archive, path: "arquivar"
        patch :restore, path: "reativar"
      end
      scope module: :customers do
        resources :locations, path: "locais", only: %i[new create edit update] do
          patch :archive, on: :member, path: "arquivar"
          get :options, on: :collection, path: "opcoes"
        end
        resources :contacts, path: "contatos", only: %i[new create edit update] do
          patch :archive, on: :member, path: "arquivar"
        end
      end
    end
    resources :equipment, path: "equipamentos" do
      member do
        get :move, path: "mover"
        patch :relocate, path: "mover"
        patch :change_status, path: "estado"
        patch :archive, path: "arquivar"
        patch :restore, path: "reativar"
      end
    end
    resources :catalog_items, path: "catalogo", except: %i[show destroy]
    resources :quotes, path: "orcamentos", only: %i[index new create show] do
      member do
        patch :update_terms, path: "condicoes"
        post :send_version, path: "enviar"
        post :new_version, path: "nova-versao"
        post :send_portal_link, path: "enviar-link"
        patch :cancel, path: "cancelar"
        post :convert, path: "converter"
        get "versoes/:version/pdf", action: :pdf, as: :pdf
      end
      scope module: :quotes do
        resources :items, path: "itens", only: %i[create destroy]
        resources :decisions, path: "decisoes", only: :create
      end
    end
    resources :service_types, path: "tipos-de-servico", only: %i[index new create edit update]
    resources :work_orders, path: "ordens-de-servico", only: %i[index new create show] do
      member do
        patch :update_report, path: "registro-tecnico"
        patch :change_status, path: "situacao"
        post :complete, path: "concluir"
        patch :cancel, path: "cancelar"
        patch :reopen, path: "reabrir"
      end
      scope module: :work_orders do
        resources :items, path: "itens", only: :create do
          patch :decide, on: :member, path: "decisao"
        end
        resources :checklist_items, path: "checklist", only: :update
        resources :assignments, path: "tecnicos", only: %i[create destroy]
        resources :stock_reservations, path: "reservas", only: :create do
          patch :release, on: :member, path: "liberar"
        end
        resources :material_consumptions, path: "consumos", only: :create do
          patch :restock, on: :member, path: "devolver"
        end
        resources :expenses, path: "despesas", only: :create
        resources :evidences, path: "anexos", only: %i[create show destroy]
        resources :reports, path: "relatorios", only: :show
      end
      resources :visits, path: "visitas", only: %i[new create edit update] do
        get :suggestions, on: :collection, path: "sugestoes"
        member do
          patch :start, path: "iniciar"
          patch :finish, path: "finalizar"
          patch :cancel, path: "cancelar"
        end
      end
    end
    resources :agenda, only: :index, path: "agenda"
    resources :absences, path: "ausencias", only: %i[index create destroy]
    resources :technicians, path: "tecnicos", only: %i[index edit update]
    resources :teams, path: "equipes", only: %i[create destroy]
    scope "estoque" do
      resources :warehouses, path: "depositos", only: %i[index new create edit update]
      resources :stock_movements, path: "movimentacoes", only: :index
      scope module: :stock, as: :stock do
        resources :receipts, path: "entradas", only: %i[new create]
        resources :transfers, path: "transferencias", only: %i[new create]
        resources :adjustments, path: "ajustes", only: %i[new create]
      end
    end
    resources :stock_balances, path: "estoque", only: :index do
      patch :minimum, on: :collection, path: "minimo"
    end
    resources :contracts, path: "contratos", except: :destroy do
      patch :change_status, on: :member, path: "situacao"
      resources :plans, path: "planos", module: :contracts, only: %i[new create show edit update] do
        post :generate, on: :member, path: "gerar"
      end
    end
    resources :receivables, path: "financeiro", only: %i[index show new create] do
      patch :cancel, on: :member, path: "cancelar"
      scope module: :receivables do
        resources :payments, path: "pagamentos", only: %i[new create] do
          patch :refund, on: :member, path: "estornar"
        end
        patch "estornos/:id/resolver", to: "refunds#resolve", as: :resolve_refund
        resources :discounts, path: "descontos", only: %i[new create]
        resources :invoices, path: "notas-fiscais", only: :create
        post "notas-fiscais/:id/consultar", to: "invoices#sync", as: :sync_invoice
        patch "notas-fiscais/:id/cancelar", to: "invoices#cancel", as: :cancel_invoice
        resources :charges, path: "cobrancas", only: :create do
          member do
            post :simulate, path: "simular-pagamento"
            post :sync, path: "consultar"
          end
        end
      end
    end
    resource :payment_integration, path: "configuracoes/pagamentos", only: %i[edit update]
    resource :fiscal_settings, path: "configuracoes/nota-fiscal", only: %i[edit update]
    resource :sla_settings, path: "configuracoes/sla", only: %i[show update]
    resource :subscription, path: "configuracoes/assinatura", only: %i[show update]
    post "configuracoes/assinatura/faturas/:id/simular-pagamento", to: "subscriptions#simulate_invoice_payment",
      as: :simulate_subscription_invoice_payment
    resource :integrations, path: "configuracoes/integracoes", only: :show do
      post :create_credential, path: "credenciais"
      patch "credenciais/:id/revogar", action: :revoke_credential, as: :revoke_credential
      post :create_endpoint, path: "webhooks"
      patch "webhooks/:id/alternar", action: :toggle_endpoint, as: :toggle_endpoint
      post "entregas/:id/reenviar", action: :redeliver, as: :redeliver
      post :rotate_payment_token, path: "token-pagamentos"
    end
    resources :holidays, path: "configuracoes/sla/feriados", only: %i[create destroy]
    namespace :field, path: "campo" do
      root "agenda#show"
      resources :work_orders, path: "ordens", only: :show
      resources :operations, path: "operacoes", only: :create
    end
    get "relatorios", to: "reports#index", as: :reports
    get "relatorios/:relatorio/exportar", to: "reports#export", as: :export_report
    resources :audit_events, path: "auditoria", only: :index
    resources :outbox_events, path: "eventos", only: %i[index show] do
      patch :reprocess, on: :member, path: "reprocessar"
    end
    resources :notifications, path: "notificacoes", only: %i[index update] do
      patch :read_all, on: :collection, path: "marcar-todas"
    end
  end

  # Customer portal: separate, restricted session obtained from an e-mailed link.
  namespace :portal, path: "portal" do
    get "acesso/:token", to: "access#show", as: :access
    post "acesso/:token", to: "access#create", as: nil
    delete "sair", to: "sessions#destroy", as: :sign_out
    get "saiu", to: "sessions#show", as: :signed_out
    root "home#show"
    resources :quotes, path: "orcamentos", only: %i[index show] do
      post :decide, on: :member, path: "decisao"
      get "versoes/:version/pdf", action: :pdf, as: :pdf, on: :member
    end
    resources :work_orders, path: "chamados", path_names: { new: "novo" }, only: %i[index show new create] do
      resources :reports, path: "relatorios", only: :show
    end
    resources :equipment, path: "equipamentos", only: %i[index show]
    resources :visits, path: "visitas", only: :index
    resources :receivables, path: "cobrancas", only: :index
  end

  # Public API (token authentication, JSON only).
  namespace :api, defaults: { format: :json } do
    namespace :v1 do
      get "openapi", to: "docs#show", defaults: { format: :yaml }
      resources :customers, only: %i[index show]
      resources :equipment, only: :index
      resources :work_orders, only: %i[index show create]
      resources :receivables, only: :index
    end
  end

  # Provider notifications (authenticated by provider token).
  post "webhooks/asaas", to: "webhooks/asaas#create", as: :asaas_webhook
  post "webhooks/plataforma/asaas", to: "webhooks/platform_asaas#create", as: :platform_asaas_webhook
end
