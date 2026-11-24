# Puma configuration. Threads must not exceed the database pool (DB_POOL).
threads_count = Integer(ENV.fetch("RAILS_MAX_THREADS", 3))
threads threads_count, threads_count

port ENV.fetch("PORT", 3000)

workers Integer(ENV.fetch("WEB_CONCURRENCY", 0))
preload_app! if Integer(ENV.fetch("WEB_CONCURRENCY", 0)).positive?

# Graceful shutdown window for in-flight requests.
worker_shutdown_timeout Integer(ENV.fetch("PUMA_SHUTDOWN_TIMEOUT", 25))

plugin :tmp_restart

pidfile ENV["PIDFILE"] if ENV["PIDFILE"]
