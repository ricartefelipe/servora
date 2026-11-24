Rails.application.routes.draw do
  get "up" => "health#live", as: :liveness
  get "ready" => "health#ready", as: :readiness

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
        sessions: "users/sessions", registrations: "users/registrations", confirmations: "users/confirmations",
        unlocks: "users/unlocks", passwords: "users/passwords"
      }
  end

  devise_scope :user do
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
    root "home#show"
    resources :quotes, path: "orcamentos", only: %i[index show] do
      post :decide, on: :member, path: "decisao"
    end
  end

  root "pages#home"
end
