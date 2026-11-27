# frozen_string_literal: true

# Living demonstration data: about six weeks of requests, quotes, visits
# (today's included), execution, billing, receipts, SLA deadlines and stock
# movements, recorded through the use cases relative to the run instant (only
# what has already happened at that instant). Idempotent: each organization's
# story is skipped once recorded. Disable with SEED_DEMO_ACTIVITY=0. In demo
# mode, Demo::AdvanceStoryJob applies the rest of today's events as their time
# comes (docs/RUNBOOKS.md, "Demonstração pública").
#
# When db:prepare seeds a brand-new database it connects with the owner role,
# which is not subject to Row-Level Security; the story waits for the seed run
# made with the application role (bin/db-prepare --seed).
require_relative "support/demo_activity"

if !Seeds::DemoActivity.enabled?
  puts "Atividade de demonstração desativada (SEED_DEMO_ACTIVITY=0)."
elsif ENV.fetch("SERVORA_DB_ROLE", "app") == "owner"
  puts "Atividade de demonstração aguardando a carga com o papel da aplicação (bin/db-prepare --seed)."
else
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  recorded = Seeds::DemoActivity.call
  seconds = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round
  puts(recorded.values.any? ? "Atividade de demonstração registrada (#{seconds} s)." : "Atividade de demonstração já existente.")
end
