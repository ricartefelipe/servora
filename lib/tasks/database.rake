# frozen_string_literal: true

namespace :db do
  namespace :privileges do
    desc "Grant runtime privileges to the application role and load platform reference data (SERVORA_DB_ROLE=owner)"
    task apply: :load_config do
      app_role = ENV.fetch("DB_APP_USER", "servora_app")

      ActiveRecord::Base.configurations.configs_for(env_name: Rails.env).each do |db_config|
        next unless db_config.database_tasks?

        ActiveRecord::Base.establish_connection(db_config)
        Servora::DatabasePrivileges.new(connection: ActiveRecord::Base.connection, app_role:).apply!
        Servora::ReferenceData.load!(ActiveRecord::Base.connection) if db_config.name == "primary"
        puts "Privileges applied to #{app_role} on #{db_config.database}"
      end
    ensure
      ActiveRecord::Base.establish_connection(Rails.env.to_sym)
    end
  end

  desc "Fail when db/structure.sql differs from what the migrations produce"
  task verify_structure: :load_config do
    structure = Rails.root.join("db/structure.sql")
    before = structure.read
    Rake::Task["db:schema:dump"].invoke
    after = structure.read
    abort "db/structure.sql is out of date. Run migrations and commit the dump." unless before == after
    puts "db/structure.sql is consistent with the migrations."
  end
end
