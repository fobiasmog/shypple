# frozen_string_literal: true

# Shypple sailing route finder: answers cheapest-direct, cheapest and fastest
# route questions from a MapReduce feed and remembers unanswered searches.
module Shypple
end

require_relative "route_finder/sailing"
require_relative "route_finder/route"
require_relative "route_finder/query"
require_relative "route_finder/feed"
require_relative "route_finder/currency_converter"
require_relative "route_finder/criteria"
require_relative "route_finder/route_finder"
require_relative "route_finder/saved_search_store"
require_relative "route_finder/presenter"
require_relative "route_finder/cli"
