# frozen_string_literal: true

require "redis"

module Shypple
  # Persistence for searches that had no result, so later feeds can fulfil
  # them. The CLI depends only on this three-method contract:
  #   save(query)    -> idempotent; an existing search keeps its first save time
  #   pending        -> saved queries, oldest first
  #   remove(query)  -> true only for the caller that actually removed it
  # and on Unavailable, raised when the storage can't be reached.
  module SavedSearchStore
    class Unavailable < StandardError; end

    # One Redis sorted set: members are query keys, scores are save times.
    class RedisStore
      DEFAULT_KEY = "route_finder:saved_searches"

      def initialize(redis, key: DEFAULT_KEY)
        @redis = redis
        @key = key
      end

      # NX never updates an existing member, so the first save time stays.
      def save(query) = reachable { @redis.zadd(@key, Time.now.to_f, query.key, nx: true) }

      def pending = reachable { @redis.zrange(@key, 0, -1).map { |key| Query.from_key(key) } }

      # ZREM succeeds for one caller only, so concurrent runs notify once.
      def remove(query) = reachable { @redis.zrem(@key, query.key) }

      private

      def reachable
        yield
      rescue Redis::BaseConnectionError => e
        raise Unavailable, e.message
      end
    end

    # Same contract in process memory; the store used by the specs.
    class MemoryStore
      def initialize
        @searches = {}
      end

      def save(query) = @searches[query.key] ||= query
      def pending = @searches.values
      # "remove", not "removed?": the store contract mirrors ZREM, which reports success.
      def remove(query) = !@searches.delete(query.key).nil? # rubocop:disable Naming/PredicateMethod
    end
  end
end
