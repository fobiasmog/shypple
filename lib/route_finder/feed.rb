# frozen_string_literal: true

require "bigdecimal"
require "date"
require "json"

module Shypple
  Feed = Data.define(:sailings, :exchange_rates)

  # The MapReduce feed, normalized: sailings in feed order with their rate
  # attached, and EUR-based exchange rates keyed by Date. Whether a sailing is
  # usable is left to each criterion (a missing exchange rate matters for cost,
  # not for speed), so nothing is filtered out here.
  class Feed
    class Error < StandardError; end

    def self.load(path)
      data = JSON.parse(File.read(path), decimal_class: BigDecimal)
      new(sailings: build_sailings(data), exchange_rates: exchange_rates_by_date(data))
    rescue SystemCallError, JSON::ParserError, KeyError, Date::Error => e
      raise Error, "Cannot load feed #{path}: #{e.message}"
    end

    def self.build_sailings(data)
      rates = latest_rates(data.fetch("rates"))
      data.fetch("sailings").map { |entry| build_sailing(entry, rates[entry.fetch("sailing_code")]) }.freeze
    end

    def self.exchange_rates_by_date(data)
      data.fetch("exchange_rates").transform_keys { |date| Date.iso8601(date) }.freeze
    end

    # Rates run oldest to newest, so for a duplicated sailing code the last
    # entry wins: a later pair overwrites an earlier one with the same key.
    def self.latest_rates(entries)
      entries.to_h { |entry| [entry.fetch("sailing_code"), entry] }
    end

    def self.build_sailing(entry, rate)
      Sailing.new(
        code: entry.fetch("sailing_code"),
        origin: entry.fetch("origin_port"),
        destination: entry.fetch("destination_port"),
        departure_date: Date.iso8601(entry.fetch("departure_date")),
        arrival_date: Date.iso8601(entry.fetch("arrival_date")),
        rate: rate&.fetch("rate"),
        currency: rate&.fetch("rate_currency")
      )
    end

    private_class_method :build_sailings, :exchange_rates_by_date, :latest_rates, :build_sailing
  end
end
