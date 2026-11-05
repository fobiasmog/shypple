# frozen_string_literal: true

module Shypple
  # One scheduled voyage between two ports. `rate` keeps the feed's original
  # string (e.g. "97453") so output echoes the feed exactly; it is nil when the
  # feed has no rate entry for this sailing.
  Sailing = Data.define(:code, :origin, :destination, :departure_date, :arrival_date, :rate, :currency) do
    def quotable? = !rate.nil?
  end
end
