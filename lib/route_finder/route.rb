# frozen_string_literal: true

module Shypple
  # An ordered list of connecting sailings from origin to destination.
  Route = Data.define(:legs) do
    def initialize(legs:) = super(legs: legs.dup.freeze)

    def departure_date = legs.first.departure_date
    def arrival_date = legs.last.arrival_date

    # From first departure to last arrival, so waiting time in port counts.
    def journey_days = (arrival_date - departure_date).to_i
  end
end
