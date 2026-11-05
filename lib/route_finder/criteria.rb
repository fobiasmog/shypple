# frozen_string_literal: true

module Shypple
  # Search criteria (Strategy pattern, duck-typed). Each criterion answers:
  #   max_legs              -> nil for unlimited, or the maximum number of legs
  #   eligible?(sailing)    -> may this sailing appear in a route?
  #   skip_reason(sailing)  -> why an ineligible sailing was left out
  #   score(route)          -> Comparable, lower is better
  # Adding a criterion means one class plus one BUILDERS entry; RouteFinder
  # does not change.
  module Criteria
    NO_RATE = "no rate in the feed"

    # Lowest total EUR cost. Legs that can't be priced in EUR are ineligible.
    class Cheapest
      attr_reader :max_legs

      def initialize(converter, max_legs: nil)
        @converter = converter
        @max_legs = max_legs
      end

      def eligible?(sailing) = sailing.quotable? && !@converter.to_eur(sailing).nil?

      def skip_reason(sailing)
        return NO_RATE unless sailing.quotable?

        "no #{sailing.currency} exchange rate for #{sailing.departure_date.iso8601}"
      end

      def score(route) = route.legs.sum { |leg| @converter.to_eur(leg) }
    end

    # Shortest journey from first departure to last arrival. Prices don't
    # matter, so only legs without a rate are ineligible.
    class Fastest
      def max_legs = nil
      def eligible?(sailing) = sailing.quotable?
      def skip_reason(_sailing) = NO_RATE
      def score(route) = route.journey_days
    end

    BUILDERS = {
      "cheapest-direct" => ->(converter) { Cheapest.new(converter, max_legs: 1) },
      "cheapest" => ->(converter) { Cheapest.new(converter) },
      "fastest" => ->(_converter) { Fastest.new }
    }.freeze

    # Known before the feed is loaded, so input can be validated first.
    NAMES = BUILDERS.keys.freeze

    def self.registry(converter) = BUILDERS.transform_values { |build| build.call(converter) }
  end
end
