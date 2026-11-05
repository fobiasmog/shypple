# frozen_string_literal: true

require "date"

# Small factories so specs can describe sailings in one line.
module Builders
  def sailing(code, origin, destination, departure, arrival, rate: "100.00", currency: "EUR")
    Shypple::Sailing.new(
      code:, origin:, destination:,
      departure_date: Date.iso8601(departure), arrival_date: Date.iso8601(arrival),
      rate:, currency:
    )
  end

  def route(*legs) = Shypple::Route.new(legs:)
end

RSpec.configure { |config| config.include Builders }
