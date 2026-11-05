# frozen_string_literal: true

RSpec.describe Shypple::Route do
  let(:first_leg) { sailing("AAAA", "CNSHA", "ESBCN", "2022-01-01", "2022-01-06") }
  let(:second_leg) { sailing("BBBB", "ESBCN", "NLRTM", "2022-01-21", "2022-01-26") }

  it "departs with its first leg and arrives with its last leg" do
    trip = route(first_leg, second_leg)

    expect([trip.departure_date, trip.arrival_date]).to eq([Date.new(2022, 1, 1), Date.new(2022, 1, 26)])
  end

  it "counts waiting time in port: 10 days at sea plus 15 days in port is a 25-day journey" do
    expect(route(first_leg, second_leg).journey_days).to eq(25)
  end

  it "keeps its legs frozen" do
    expect(route(first_leg).legs).to be_frozen
  end
end
