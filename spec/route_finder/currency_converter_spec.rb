# frozen_string_literal: true

RSpec.describe Shypple::CurrencyConverter do
  subject(:converter) { described_class.new(Shypple::Feed.load(Paths::SAMPLE_FEED).exchange_rates) }

  def to_eur(rate, currency, departing:)
    converter.to_eur(sailing("TEST", "CNSHA", "NLRTM", departing, "2023-12-31", rate:, currency:))
  end

  it "divides a USD rate by the USD rate for its departure date (ABCD: 589.30 / 1.126)" do
    expect(to_eur("589.30", "USD", departing: "2022-02-01"))
      .to be_a(BigDecimal).and be_within(BigDecimal("0.000001")).of(BigDecimal("523.357016"))
  end

  it "divides a JPY rate by the JPY rate for its departure date (IJKL: 97453 / 131.2)" do
    expect(to_eur("97453", "JPY", departing: "2022-01-31")).to be_within(BigDecimal("0.005")).of(BigDecimal("742.78"))
  end

  it "returns an EUR rate unchanged, even on a date with no exchange rates" do
    expect(to_eur("261.96", "EUR", departing: "2023-06-01")).to eq(BigDecimal("261.96"))
  end

  it "returns nil when the departure date has no exchange rates" do
    expect(to_eur("69.96", "USD", departing: "2022-02-10")).to be_nil
  end

  it "returns nil when the departure date has no rate for the currency" do
    expect(to_eur("50.00", "GBP", departing: "2022-01-29")).to be_nil
  end

  it "returns nil for a sailing without a rate" do
    expect(to_eur(nil, nil, departing: "2022-01-29")).to be_nil
  end
end
