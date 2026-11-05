# frozen_string_literal: true

module Shypple
  # One run: read the query, load the feed, report saved searches the feed
  # now fulfils, answer the query on stdout, save it if it had no answer.
  # stdout carries only the JSON result; everything else goes to stderr.
  class CLI
    def initialize(feed_path:, store:, stdin:, stdout:, stderr:)
      @feed_path = feed_path
      @store = store
      @stdin = stdin
      @stdout = stdout
      @stderr = stderr
      @presenter = Presenter.new
    end

    # Returns the exit status.
    def run
      query = Query.parse(@stdin, Criteria::NAMES)
      search = searcher(Feed.load(@feed_path))
      notify_fulfilled(search)
      answer(query, search)
      0
    rescue Query::Invalid, Feed::Error => e
      @stderr.puts "Error: #{e.message}"
      1
    end

    private

    def searcher(feed)
      finder = RouteFinder.new(feed.sailings)
      criteria = Criteria.registry(CurrencyConverter.new(feed.exchange_rates))
      ->(query) { finder.find(query.origin, query.destination, criteria.fetch(query.criterion)) }
    end

    def answer(query, search)
      result = search.call(query)
      warn_skipped(result.skipped)
      @stdout.puts @presenter.render(result.route)
      save_unfulfilled(query) unless result.route
    end

    # Only the run whose remove succeeds reports a search, so it is reported once.
    def notify_fulfilled(search)
      @store.pending.each do |saved|
        route = search.call(saved).route
        @stderr.print @presenter.notification(saved, route) if route && @store.remove(saved)
      end
    rescue SavedSearchStore::Unavailable => e
      @stderr.puts "Warning: saved searches could not be checked: #{e.message}"
    end

    def warn_skipped(skipped)
      skipped.each do |sailing, reason|
        @stderr.puts "Warning: skipped #{sailing.code} (#{sailing.origin} -> #{sailing.destination}, " \
                     "departing #{sailing.departure_date.iso8601}): #{reason}"
      end
    end

    def save_unfulfilled(query)
      @store.save(query)
      @stderr.puts "No route found for #{query}. Search saved; you will be notified when an option becomes available."
    rescue SavedSearchStore::Unavailable => e
      @stderr.puts "Warning: the search could not be saved: #{e.message}"
    end
  end
end
