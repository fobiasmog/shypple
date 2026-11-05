FROM ruby:3.4-slim

# Native extensions (bigdecimal, json, prism, racc) need a compiler.
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# All groups are installed so one image runs both the app and the test suite.
COPY Gemfile Gemfile.lock ./
RUN bundle config set --local frozen true \
 && bundle install --jobs 4

COPY . .

ENTRYPOINT ["bin/route_finder"]
