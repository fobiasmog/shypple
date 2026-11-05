# frozen_string_literal: true

module Shypple
  Query = Data.define(:origin, :destination, :criterion)

  # A user's search. Reopened (rather than given a Data.define block) so that
  # Invalid and KEY_SEPARATOR are constants of Query, not of Shypple.
  class Query
    class Invalid < StandardError; end

    KEY_SEPARATOR = ":"

    # Reads exactly three lines with #gets, so an interactive session gets an
    # answer right after the third line instead of waiting for end of input.
    def self.parse(io, criteria_names)
      origin, destination, criterion = Array.new(3) { read_line(io) }
      query = new(origin: origin.upcase, destination: destination.upcase, criterion: criterion.downcase)
      query.validate!(criteria_names)
    end

    def self.from_key(key)
      origin, destination, criterion = key.split(KEY_SEPARATOR, 3)
      new(origin:, destination:, criterion:)
    end

    def self.read_line(io)
      line = io.gets
      raise Invalid, "Missing input: expected three lines (origin port, destination port, criterion)" unless line

      line.strip
    end
    private_class_method :read_line

    def key = [origin, destination, criterion].join(KEY_SEPARATOR)
    def to_s = "#{origin} -> #{destination} (#{criterion})"

    def validate!(criteria_names)
      raise Invalid, "Origin port must not be blank" if origin.empty?
      raise Invalid, "Destination port must not be blank" if destination.empty?
      raise Invalid, "Origin and destination must differ (both are #{origin})" if origin == destination
      unless criteria_names.include?(criterion)
        raise Invalid, "Unknown criterion '#{criterion}'. Supported: #{criteria_names.join(", ")}"
      end

      self
    end
  end
end
