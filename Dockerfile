FROM ruby:3.4-slim
RUN apt-get update -qq && apt-get install -y --no-install-recommends build-essential libpq-dev curl && rm -rf /var/lib/apt/lists/*
WORKDIR /app
ENV BUNDLE_PATH=/usr/local/bundle
COPY Gemfile Gemfile.lock ./
RUN bundle install
COPY . .
RUN SECRET_KEY_BASE_DUMMY=1 RAILS_ENV=production bundle exec rails assets:precompile
RUN groupadd --system app && useradd --system --gid app --create-home app && chown -R app:app /app
USER app
EXPOSE 3000
CMD ["bin/rails", "server", "-b", "0.0.0.0"]
