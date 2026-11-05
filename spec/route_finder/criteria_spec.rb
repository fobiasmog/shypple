# frozen_string_literal: true

RSpec.describe Shypple::Criteria do
  let(:converter) { Shypple::CurrencyConverter.new(Shypple::Feed.load(Paths::SAMPLE_FEED).exchange_rates) }
  let(:erxq) { sailing("ERXQ", "CNSHA", "ESBCN", "2022-01-29", "2022-02-12", rate: "261.96", currency: "EUR") }
  let(:etrg) { sailing("ETRG", "ESBCN", "NLRTM", "2022-02-16", "2022-02-20", rate: "69.96", currency: "USD") }
  let(:no_exchange_rate) do
    sailing("ETRG", "ESBCN", "NLRTM", "2022-02-17", "2022-02-20", rate: "69.96", currency: "USD")
  end
  let(:unquoted) { sailing("ZZZZ", "ESBCN", "NLRTM", "2022-02-16", "2022-02-20", rate: nil, currency: nil) }

  describe ".registry" do
    subject(:registry) { described_class.registry(converter) }

    it "offers exactly the supported criterion names" do
      expect(registry.keys).to eq(described_class::NAMES)
    end

    it "lists cheapest-direct, cheapest and fastest" do
      expect(described_class::NAMES).to eq(%w[cheapest-direct cheapest fastest])
    end

    it "limits cheapest-direct to one leg and leaves the others unlimited" do
      expect(registry.transform_values(&:max_legs)).to eq("cheapest-direct" => 1, "cheapest" => nil, "fastest" => nil)
    end

    described_class::NAMES.each do |name|
      context "with #{name}" do
        let(:criterion) { registry.fetch(name) }

        it_behaves_like "a route criterion"
      end
    end
  end

  describe Shypple::Criteria::Cheapest do
    subject(:criterion) { described_class.new(converter) }

    it "scores a route by the sum of its legs in EUR, unrounded" do
      expect(criterion.score(route(erxq, etrg))).to be_within(BigDecimal("0.000001")).of(BigDecimal("322.890152"))
    end

    it "accepts an EUR leg on a date with no exchange rates" do
      eur_only = sailing("EURO", "CNSHA", "ESBCN", "2023-06-01", "2023-06-20", rate: "261.96", currency: "EUR")

      expect(criterion.eligible?(eur_only)).to be(true)
    end

    it "rejects a leg whose departure date has no exchange rate, naming currency and date" do
      expect(criterion.eligible?(no_exchange_rate)).to be(false)
      expect(criterion.skip_reason(no_exchange_rate)).to eq("no USD exchange rate for 2022-02-17")
    end

    it "rejects a leg without a rate" do
      expect(criterion.skip_reason(unquoted)).to eq("no rate in the feed")
    end
  end

  describe Shypple::Criteria::Fastest do
    subject(:criterion) { described_class.new }

    it "scores a route by its journey days, waiting time included" do
      expect(criterion.score(route(erxq, etrg))).to eq(22)
    end

    it "accepts a leg that has no exchange rate" do
      expect(criterion.eligible?(no_exchange_rate)).to be(true)
    end

    it "rejects a leg without a rate" do
      expect(criterion.eligible?(unquoted)).to be(false)
      expect(criterion.skip_reason(unquoted)).to eq("no rate in the feed")
    end
  end
end
