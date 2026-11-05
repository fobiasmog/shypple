# frozen_string_literal: true

require "tempfile"

RSpec.describe Shypple::Feed do
  describe ".load" do
    subject(:feed) { described_class.load(Paths::SAMPLE_FEED) }

    it "loads every sailing in feed order" do
      expect(feed.sailings.map(&:code)).to eq(%w[ABCD EFGH IJKL MNOP QRST ERXQ ETRF ETRG ETRB])
    end

    it "builds sailings with ports, dates, rate and currency" do
      expect(feed.sailings.find { |s| s.code == "IJKL" }).to have_attributes(
        origin: "CNSHA", destination: "NLRTM",
        departure_date: Date.new(2022, 1, 31), arrival_date: Date.new(2022, 2, 28),
        rate: "97453", currency: "JPY"
      )
    end

    it "uses the last rate when a sailing code has several (MNOP: 456.78 then 812.00)" do
      expect(feed.sailings.find { |s| s.code == "MNOP" }).to have_attributes(rate: "812.00", currency: "USD")
    end

    it "keys exchange rates by date and holds them as BigDecimal" do
      usd = feed.exchange_rates.dig(Date.new(2022, 1, 29), "usd")

      expect(usd).to be_a(BigDecimal).and eq(BigDecimal("1.1138"))
    end

    it "marks a sailing with no rate entry as unquotable" do
      unquoted = described_class.load(fixture_path("sailing_without_rate")).sailings.first

      expect(unquoted).to have_attributes(code: "ZZZZ", rate: nil, currency: nil, quotable?: false)
    end

    it "fails with an error naming the path when the file is missing" do
      expect { described_class.load("/no/such/feed.json") }
        .to raise_error(described_class::Error, %r{/no/such/feed\.json})
    end

    it "fails with an error naming the path when the file is not valid JSON" do
      Tempfile.create(["broken", ".json"]) do |file|
        file.write("{ not json")
        file.flush

        expect { described_class.load(file.path) }
          .to raise_error(described_class::Error, /#{Regexp.escape(file.path)}: \S/)
      end
    end

    it "fails with an error naming the path when a section is missing" do
      Tempfile.create(["partial", ".json"]) do |file|
        file.write('{"sailings": []}')
        file.flush

        expect { described_class.load(file.path) }
          .to raise_error(described_class::Error, /#{Regexp.escape(file.path)}.*rates/)
      end
    end
  end
end
