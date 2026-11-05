# frozen_string_literal: true

require "json"

module Shypple
  # Formats routes for people: the stdout JSON and the saved-search
  # notification share one leg format, so it is defined once.
  class Presenter
    def render(route)
      JSON.pretty_generate((route&.legs || []).map { |leg| leg_hash(leg) })
    end

    def notification(query, route)
      "Saved search now available: #{query}\n#{render(route)}\n"
    end

    private

    def leg_hash(sailing)
      {
        origin_port: sailing.origin,
        destination_port: sailing.destination,
        departure_date: sailing.departure_date.iso8601,
        arrival_date: sailing.arrival_date.iso8601,
        sailing_code: sailing.code,
        rate: sailing.rate,
        rate_currency: sailing.currency
      }
    end
  end
end
