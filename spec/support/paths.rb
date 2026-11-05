# frozen_string_literal: true

# Locations of the sample feed and the small fixture feeds.
module Paths
  SAMPLE_FEED = File.expand_path("../../response.json", __dir__)

  def fixture_path(name) = File.expand_path("../fixtures/#{name}.json", __dir__)
end

RSpec.configure { |config| config.include Paths }
