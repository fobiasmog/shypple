# frozen_string_literal: true

require "bigdecimal"

module Shypple
  # The only place that knows the exchange-rate rules: rates are EUR-based,
  # chosen by the sailing's departure date, and EUR needs no conversion.
  class CurrencyConverter
    BASE_CURRENCY = "EUR"

    # exchange_rates: { Date => { "usd" => BigDecimal, ... } }
    def initialize(exchange_rates)
      @exchange_rates = exchange_rates
    end

    # The sailing's cost in EUR as a BigDecimal, or nil when it can't be priced.
    def to_eur(sailing)
      return unless sailing.quotable?

      amount = BigDecimal(sailing.rate)
      return amount if sailing.currency.casecmp?(BASE_CURRENCY)

      exchange_rate = @exchange_rates.dig(sailing.departure_date, sailing.currency.downcase)
      exchange_rate && (amount / exchange_rate)
    end
  end
end
