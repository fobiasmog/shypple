# frozen_string_literal: true

require "redis"

# Specs tagged :redis use database 15, flushed before each example, so the
# saved searches in database 0 are never touched. They are skipped when Redis
# can't be reached (e.g. running rspec outside docker compose).
module RedisTestDatabase
  URL = ENV.fetch("REDIS_URL", "redis://localhost:6379/0")

  def self.client = @client ||= Redis.new(url: URL, db: 15)

  def self.reachable?
    return @reachable if defined?(@reachable)

    @reachable = begin
      client.ping == "PONG"
    rescue Redis::BaseConnectionError
      false
    end
  end
end

RSpec.configure do |config|
  config.before(:each, :redis) do
    unless RedisTestDatabase.reachable?
      skip "Redis is not reachable at #{RedisTestDatabase::URL}; run the suite through docker compose"
    end

    RedisTestDatabase.client.flushdb
  end
end
