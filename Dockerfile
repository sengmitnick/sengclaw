# syntax=docker/dockerfile:1
# Ruby 3.3.5 + Rails 7.2 production image
FROM ghcr.io/clacky-ai/rails-base-template:latest

# System dependencies: PostgreSQL client, Node.js 20, build tools, jemalloc
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      build-essential \
      libpq-dev \
      libvips42 \
      libjemalloc2 \
      curl \
      git \
      ca-certificates \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install -g npm@10 \
    && rm -rf /var/lib/apt/lists/*

# Create app user (non-root)
RUN groupadd --system --gid 1000 ruby && \
    useradd --system --uid 1000 --gid ruby --create-home --shell /bin/bash ruby

WORKDIR /app

ENV RAILS_ENV="production" \
    NODE_ENV="production" \
    PORT="3000" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test"

# Install gems
COPY --chown=ruby:ruby Gemfile Gemfile.lock ./
RUN bundle install --jobs=4 --retry=3 && \
    bundle exec bootsnap precompile --gemfile

# Install npm packages
COPY --chown=ruby:ruby package.json package-lock.json ./
RUN npm ci --production=false

# Copy application code
COPY --chown=ruby:ruby . .

# Precompile bootsnap & assets
RUN bundle exec bootsnap precompile app/ lib/ && \
    SECRET_KEY_BASE_DUMMY=1 bundle exec rails assets:precompile

USER ruby

ENTRYPOINT ["/app/bin/docker-entrypoint"]

EXPOSE 3000
CMD ["./bin/rails", "server"]
