Rails.application.config.active_record.action_on_strict_loading_violation =
  Rails.env.production? ? :log : :raise
