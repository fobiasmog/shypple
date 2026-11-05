# frozen_string_literal: true

module Shypple
  # Finds the best route between two ports for a criterion.
  #
  # A depth-first search walks sailings in feed order, so candidate routes come
  # out ordered by the feed positions of their legs. Selection keeps a route
  # only when it scores strictly lower, so on a tie the first one found wins.
  class RouteFinder
    # route: the best Route, or nil. skipped: { Sailing => reason } for every
    # sailing that kept an otherwise valid route out, each named once.
    Result = Data.define(:route, :skipped)

    def initialize(sailings)
      @departures = sailings.group_by(&:origin)
    end

    def find(origin, destination, criterion)
      skipped = {}
      candidates = enum_for(:each_path, destination, criterion.max_legs, [origin], []).filter_map do |legs|
        rejected = legs.reject { |leg| criterion.eligible?(leg) }
        rejected.each { |leg| skipped[leg] ||= criterion.skip_reason(leg) }
        Route.new(legs:) if rejected.empty?
      end
      Result.new(route: best(candidates, criterion), skipped: skipped.freeze)
    end

    private

    # Yields every path from the last visited port to the destination where
    # each leg departs on or after the previous arrival and no port repeats.
    def each_path(destination, max_legs, ports, legs, &)
      return if max_legs && legs.size >= max_legs

      @departures.fetch(ports.last, []).each do |sailing|
        next if ports.include?(sailing.destination) || !connects?(legs.last, sailing)

        path = [*legs, sailing]
        if sailing.destination == destination
          yield path
        else
          each_path(destination, max_legs, [*ports, sailing.destination], path, &)
        end
      end
    end

    def connects?(previous, sailing) = previous.nil? || previous.arrival_date <= sailing.departure_date

    # Strict < keeps the earlier route on a tie.
    def best(routes, criterion)
      scored = routes.map { |route| [route, criterion.score(route)] }
      scored.reduce { |best, candidate| candidate.last < best.last ? candidate : best }&.first
    end
  end
end
