# frozen_string_literal: true

# The duck-typed contract every search criterion must honour. RouteFinder
# relies only on these four methods, so a new criterion that passes this
# group plugs in without changing the finder. Host groups provide `criterion`.
RSpec.shared_examples "a route criterion" do
  let(:priced) { sailing("PRCD", "CNSHA", "NLRTM", "2022-01-29", "2022-02-15", rate: "100.00", currency: "EUR") }
  let(:unquoted) { sailing("ZZZZ", "CNSHA", "NLRTM", "2022-01-29", "2022-02-15", rate: nil, currency: nil) }

  it "limits legs with nil (unlimited) or a positive integer" do
    expect(criterion.max_legs).to be_nil.or(be_a(Integer).and(be_positive))
  end

  it "accepts a quotable, priced sailing" do
    expect(criterion.eligible?(priced)).to be(true)
  end

  it "rejects an unquotable sailing and explains why" do
    expect(criterion.eligible?(unquoted)).to be(false)
    expect(criterion.skip_reason(unquoted)).to match(/\S/)
  end

  it "scores a route with a comparable value" do
    expect(criterion.score(route(priced))).to be_a(Comparable)
  end
end
