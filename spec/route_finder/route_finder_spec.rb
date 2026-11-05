# frozen_string_literal: true

RSpec.describe Shypple::RouteFinder do
  def search(feed_path, origin, destination, criterion_name)
    feed = Shypple::Feed.load(feed_path)
    criterion = Shypple::Criteria.registry(Shypple::CurrencyConverter.new(feed.exchange_rates)).fetch(criterion_name)
    described_class.new(feed.sailings).find(origin, destination, criterion)
  end

  def codes(result) = result.route&.legs&.map(&:code)

  def skipped_codes(result) = result.skipped.keys.map(&:code)

  # Accepts every sailing and records each candidate route in the order the
  # finder produces them. Any object with these four methods is a criterion.
  let(:recorder) do
    Class.new do
      attr_reader :candidates

      def initialize = @candidates = []
      def max_legs = nil
      def eligible?(_sailing) = true
      def skip_reason(_sailing) = "never"

      def score(route)
        @candidates << route.legs.map(&:code)
        0
      end
    end.new
  end

  describe "on the sample feed, CNSHA to NLRTM" do
    it "finds ABCD as the cheapest direct sailing (589.30 USD, about 523.36 EUR)" do
      expect(codes(search(Paths::SAMPLE_FEED, "CNSHA", "NLRTM", "cheapest-direct"))).to eq(%w[ABCD])
    end

    it "finds ERXQ then ETRG as the cheapest route (about 322.89 EUR)" do
      expect(codes(search(Paths::SAMPLE_FEED, "CNSHA", "NLRTM", "cheapest"))).to eq(%w[ERXQ ETRG])
    end

    it "finds QRST as the fastest route (17 days, against 22 for ERXQ then ETRG)" do
      result = search(Paths::SAMPLE_FEED, "CNSHA", "NLRTM", "fastest")

      expect([codes(result), result.route.journey_days]).to eq([%w[QRST], 17])
    end

    it "reports no skipped sailings" do
      results = %w[cheapest-direct cheapest fastest].map { |name| search(Paths::SAMPLE_FEED, "CNSHA", "NLRTM", name) }

      expect(results.map(&:skipped))
        .to all(be_empty)
    end
  end

  describe "when no route exists" do
    it "returns no route for cheapest-direct CNSHA to BRSSZ, which is reachable only through ESBCN" do
      expect(search(Paths::SAMPLE_FEED, "CNSHA", "BRSSZ", "cheapest-direct").route).to be_nil
    end

    it "still finds CNSHA to BRSSZ through ESBCN for cheapest" do
      expect(codes(search(Paths::SAMPLE_FEED, "CNSHA", "BRSSZ", "cheapest"))).to eq(%w[ERXQ ETRB])
    end

    it "returns no route when no sailing leaves the origin (NLRTM to CNSHA)" do
      expect(search(Paths::SAMPLE_FEED, "NLRTM", "CNSHA", "cheapest")).to have_attributes(route: nil, skipped: {})
    end
  end

  describe "connection rules" do
    it "allows a same-day transfer" do
      sailings = [
        sailing("AB01", "A", "B", "2022-02-10", "2022-02-16"),
        sailing("BC01", "B", "C", "2022-02-16", "2022-02-20")
      ]

      expect(codes(described_class.new(sailings).find("A", "C", recorder))).to eq(%w[AB01 BC01])
    end

    it "rejects a next leg that departs before the previous leg arrives" do
      sailings = [
        sailing("AB01", "A", "B", "2022-02-01", "2022-02-12"),
        sailing("BC01", "B", "C", "2022-02-10", "2022-02-20")
      ]

      expect(described_class.new(sailings).find("A", "C", recorder).route).to be_nil
    end

    it "never returns to a port it has left (A -> B -> A)" do
      sailings = [
        sailing("AB01", "A", "B", "2022-01-01", "2022-01-02"),
        sailing("BA01", "B", "A", "2022-01-03", "2022-01-04"),
        sailing("AC01", "A", "C", "2022-01-05", "2022-01-06")
      ]
      described_class.new(sailings).find("A", "C", recorder)

      expect(recorder.candidates).to eq([%w[AC01]])
    end

    it "never passes through an intermediate port twice (A -> X -> B -> X -> C)" do
      sailings = [
        sailing("AX01", "A", "X", "2022-01-01", "2022-01-02"),
        sailing("XB01", "X", "B", "2022-01-03", "2022-01-04"),
        sailing("BX01", "B", "X", "2022-01-05", "2022-01-06"),
        sailing("XC01", "X", "C", "2022-01-07", "2022-01-08")
      ]
      described_class.new(sailings).find("A", "C", recorder)

      expect(recorder.candidates).to eq([%w[AX01 XC01]])
    end

    it "produces candidates in feed order of their legs: first legs first, then second legs" do
      sailings = [
        sailing("AB01", "A", "B", "2022-01-01", "2022-01-02"),
        sailing("AC01", "A", "C", "2022-01-01", "2022-01-09"),
        sailing("BC01", "B", "C", "2022-01-03", "2022-01-04"),
        sailing("BC02", "B", "C", "2022-01-02", "2022-01-03")
      ]
      described_class.new(sailings).find("A", "C", recorder)

      expect(recorder.candidates).to eq([%w[AB01 BC01], %w[AB01 BC02], %w[AC01]])
    end
  end

  it "finds a three-leg route and returns the legs in travel order" do
    fixture = fixture_path("three_legs")

    expect(%w[cheapest fastest].map { |name| codes(search(fixture, "CNSHA", "NLRTM", name)) })
      .to all(eq(%w[LEG1 LEG2 LEG3]))
  end

  describe "ties go to the first route in feed order" do
    let(:fixture) { fixture_path("ties") }

    it "picks DDDD over the equally priced EEEE for cheapest-direct, although EEEE departs earlier" do
      expect(codes(search(fixture, "CNSHA", "NLRTM", "cheapest-direct"))).to eq(%w[DDDD])
    end

    it "picks AAAA then BBBB for cheapest, since AAAA comes first in the feed" do
      expect(codes(search(fixture, "CNSHA", "NLRTM", "cheapest"))).to eq(%w[AAAA BBBB])
    end

    it "picks AAAA then BBBB for fastest, since all three routes take 14 days" do
      expect(codes(search(fixture, "CNSHA", "NLRTM", "fastest"))).to eq(%w[AAAA BBBB])
    end
  end

  describe "sailings the criterion can't use" do
    let(:fixture) { fixture_path("missing_exchange_rate") }

    it "leaves ETRG (no USD rate for 2022-02-16) out of cheapest and returns ERXQ then ETRF" do
      result = search(fixture, "CNSHA", "NLRTM", "cheapest")

      expect(codes(result)).to eq(%w[ERXQ ETRF])
      expect(result.skipped.transform_keys(&:code)).to eq("ETRG" => "no USD exchange rate for 2022-02-16")
    end

    it "does not report ETRB, which can't be priced either but isn't on any CNSHA to NLRTM route" do
      expect(skipped_codes(search(fixture, "CNSHA", "NLRTM", "cheapest"))).not_to include("ETRB")
    end

    it "leaves fastest unaffected by missing exchange rates" do
      expect(search(fixture, "CNSHA", "NLRTM", "fastest")).to have_attributes(skipped: {})
        .and(satisfy { |result| codes(result) == %w[QRST] })
    end

    it "names a sailing once even when it sits on several candidate routes" do
      sailings = [
        sailing("AB01", "A", "B", "2022-01-01", "2022-01-02"),
        sailing("AB02", "A", "B", "2022-01-01", "2022-01-03"),
        sailing("AB03", "A", "B", "2022-01-01", "2022-01-04"),
        sailing("BC01", "B", "C", "2022-01-05", "2022-01-06", currency: "GBP")
      ]
      criterion = Shypple::Criteria::Cheapest.new(Shypple::CurrencyConverter.new({}))

      expect(skipped_codes(described_class.new(sailings).find("A", "C", criterion))).to eq(%w[BC01])
    end

    it "excludes a fast sailing without a rate from fastest and names it" do
      result = search(fixture_path("sailing_without_rate"), "CNSHA", "NLRTM", "fastest")

      expect(codes(result)).to eq(%w[QRST])
      expect(result.skipped.transform_keys(&:code)).to eq("ZZZZ" => "no rate in the feed")
    end
  end
end
