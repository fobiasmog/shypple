# frozen_string_literal: true

# A criterion that accepts every sailing and records each candidate route, as
# leg codes, in the order RouteFinder produces them. Any object with these four
# methods is a criterion, so specs can watch the enumeration itself.
class RecordingCriterion
  attr_reader :max_legs, :candidates

  def initialize(max_legs: nil)
    @max_legs = max_legs
    @candidates = []
  end

  def eligible?(_sailing) = true
  def skip_reason(_sailing) = "never"

  def score(route)
    @candidates << route.legs.map(&:code)
    0
  end
end
