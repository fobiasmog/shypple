# frozen_string_literal: true

RSpec.describe Shypple::Presenter do
  subject(:presenter) { described_class.new }

  let(:cheapest_route) do
    feed = Shypple::Feed.load(Paths::SAMPLE_FEED)
    criterion = Shypple::Criteria.registry(Shypple::CurrencyConverter.new(feed.exchange_rates)).fetch("cheapest")
    Shypple::RouteFinder.new(feed.sailings).find("CNSHA", "NLRTM", criterion).route
  end

  describe "#render" do
    it "prints the legs as pretty JSON, keys in the agreed order (sample cheapest CNSHA to NLRTM)" do
      expect(presenter.render(cheapest_route)).to eq(<<~JSON.chomp)
        [
          {
            "origin_port": "CNSHA",
            "destination_port": "ESBCN",
            "departure_date": "2022-01-29",
            "arrival_date": "2022-02-12",
            "sailing_code": "ERXQ",
            "rate": "261.96",
            "rate_currency": "EUR"
          },
          {
            "origin_port": "ESBCN",
            "destination_port": "NLRTM",
            "departure_date": "2022-02-16",
            "arrival_date": "2022-02-20",
            "sailing_code": "ETRG",
            "rate": "69.96",
            "rate_currency": "USD"
          }
        ]
      JSON
    end

    it "echoes the rate exactly as the feed quotes it (IJKL: 97453 JPY)" do
      ijkl = sailing("IJKL", "CNSHA", "NLRTM", "2022-01-31", "2022-02-28", rate: "97453", currency: "JPY")

      expect(JSON.parse(presenter.render(route(ijkl))).first).to include("rate" => "97453", "rate_currency" => "JPY")
    end

    it "prints [] when there is no route" do
      expect(presenter.render(nil)).to eq("[]")
    end
  end

  describe "#notification" do
    let(:query) { Shypple::Query.new(origin: "NLRTM", destination: "CNSHA", criterion: "cheapest") }

    it "names the search on a header line, then prints the route as on stdout" do
      expect(presenter.notification(query, cheapest_route))
        .to eq("Saved search now available: NLRTM -> CNSHA (cheapest)\n#{presenter.render(cheapest_route)}\n")
    end
  end
end
