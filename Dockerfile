# syntax=docker/dockerfile:1.12
# check=error=true

# Multi-stage image for Servora.
#
#   development  - all gem groups; used by docker-compose.yml for local work and tests
#   production   - runtime-only gems, precompiled assets, non-root user
#
# Build the production image:
#   docker build --target production -t servora:local .

ARG RUBY_VERSION=4.0.10
ARG DEBIAN_RELEASE=trixie
ARG POSTGRES_CLIENT_MAJOR=18

FROM docker.io/library/ruby:${RUBY_VERSION}-slim-${DEBIAN_RELEASE} AS base
ARG DEBIAN_RELEASE
ARG POSTGRES_CLIENT_MAJOR

WORKDIR /rails

# Runtime packages. The PostgreSQL client comes from the PGDG repository so that
# psql/pg_dump match the server major version used to load db/structure.sql.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y ca-certificates curl libjemalloc2 && \
    install -d /usr/share/postgresql-common/pgdg && \
    curl --fail --silent --show-error --location \
      -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
      https://www.postgresql.org/media/keys/ACCC4CF8.asc && \
    echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt ${DEBIAN_RELEASE}-pgdg main" \
      > /etc/apt/sources.list.d/pgdg.list && \
    apt-get update -qq && \
    apt-get install --no-install-recommends -y "postgresql-client-${POSTGRES_CLIENT_MAJOR}" && \
    ln -s "/usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2" /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV BUNDLE_PATH="/usr/local/bundle" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so" \
    LANG="C.UTF-8"

RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash

# Packages needed only to compile native gem extensions.
FROM base AS build-deps
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Development and test image: includes every gem group plus headless Chromium
# so the full suite (system specs included) can run inside the container.
FROM build-deps AS development
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y chromium fonts-liberation && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives
ENV RAILS_ENV="development" \
    BROWSER_PATH="/usr/bin/chromium"
COPY Gemfile Gemfile.lock .ruby-version ./
RUN bundle install && rm -rf "${BUNDLE_PATH}"/ruby/*/cache
RUN chown -R rails:rails "${BUNDLE_PATH}"
USER 1000:1000
EXPOSE 3000
CMD ["ruby", "bin/rails", "server", "-b", "0.0.0.0"]

# Production build stage.
FROM build-deps AS build
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_WITHOUT="development:test"
COPY Gemfile Gemfile.lock .ruby-version ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile -j 1 --gemfile
COPY . .
# Executable bits are normalised here so the image does not depend on the
# permissions of the build context file system.
RUN chmod 0755 bin/* && \
    rm -rf spec coverage && \
    bundle exec bootsnap precompile -j 1 app/ lib/ && \
    SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

FROM base AS production
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_WITHOUT="development:test"
LABEL org.opencontainers.image.title="servora" \
      org.opencontainers.image.description="Servora - gestão de serviços de campo e manutenção" \
      org.opencontainers.image.source="https://github.com/ricartefelipe/servora" \
      org.opencontainers.image.licenses="UNLICENSED"
# Ruby 4.0.10 ships json 2.18.3 as a default gem (CVE-2026-33210). The
# application loads json >= 3.1 from the bundle, so the vulnerable default copy
# is removed from the runtime image instead of being ignored by the scanner.
RUN rm -rf "$(ruby -e 'print Gem.default_specifications_dir')"/json-2.*.gemspec \
           "$(ruby -e 'print RbConfig::CONFIG["rubylibdir"]')/json.rb" \
           "$(ruby -e 'print RbConfig::CONFIG["rubylibdir"]')/json" \
           "$(ruby -e 'print RbConfig::CONFIG["archdir"]')/json"
COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails
USER 1000:1000
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s --start-period=20s --retries=3 \
  CMD curl --fail --silent http://127.0.0.1:3000/up || exit 1
ENTRYPOINT ["/rails/bin/docker-entrypoint"]
CMD ["./bin/rails", "server", "-b", "0.0.0.0"]
