# frozen_string_literal: true

# End-to-end searches through the CLI: stdin text in, stdout JSON out.
# Expected routes come from response.json and assumptions.md, not from the
# illustrative examples in CHALLENGE.md.
RSpec.describe "Searching for routes" do
  let(:store) { Shypple::SavedSearchStore::MemoryStore.new }

  def legs(run) = JSON.parse(run.stdout).map { |leg| leg["sailing_code"] }

  describe "on the sample feed, CNSHA to NLRTM" do
    it "answers cheapest-direct with ABCD (589.30 USD, about 523.36 EUR)" do
      expect(legs(run_cli("CNSHA\nNLRTM\ncheapest-direct\n", store:))).to eq(%w[ABCD])
    end

    it "answers cheapest with ERXQ then ETRG (about 322.89 EUR in total)" do
      expect(legs(run_cli("CNSHA\nNLRTM\ncheapest\n", store:))).to eq(%w[ERXQ ETRG])
    end

    it "answers fastest with QRST, 17 days door to door. CHALLENGE.md's illustrative example shows " \
       "ERXQ then ETRG, but on this feed that route takes 22 days (2022-01-29 to 2022-02-20) once the " \
       "wait in Barcelona counts as journey time (assumption #8)" do
      expect(legs(run_cli("CNSHA\nNLRTM\nfastest\n", store:))).to eq(%w[QRST])
    end

    it "accepts lower-case, padded input" do
      expect(legs(run_cli(" cnsha \nnlrtm\nCheapest\n", store:))).to eq(%w[ERXQ ETRG])
    end
  end

  it "returns a three-leg route in travel order" do
    run = run_cli("CNSHA\nNLRTM\ncheapest\n", store:, feed: fixture_path("three_legs"))

    expect(legs(run)).to eq(%w[LEG1 LEG2 LEG3])
  end

  it "breaks a tie in favour of the first route in the feed" do
    expect(legs(run_cli("CNSHA\nNLRTM\nfastest\n", store:, feed: fixture_path("ties")))).to eq(%w[AAAA BBBB])
  end

  describe "with no exchange rate for 2022-02-16" do
    let(:feed) { fixture_path("missing_exchange_rate") }

    it "returns the cheapest priceable route and names the skipped sailing on stderr only" do
      run = run_cli("CNSHA\nNLRTM\ncheapest\n", store:, feed:)

      expect(legs(run)).to eq(%w[ERXQ ETRF])
      expect(run.stderr.lines.grep(/ETRG/).size).to eq(1)
      expect(run.stderr).not_to include("ETRB")
    end

    it "leaves fastest unaffected" do
      run = run_cli("CNSHA\nNLRTM\nfastest\n", store:, feed:)

      expect([legs(run), run.stderr]).to eq([%w[QRST], ""])
    end
  end

  it "keeps a sailing without a rate out of fastest and says so" do
    run = run_cli("CNSHA\nNLRTM\nfastest\n", store:, feed: fixture_path("sailing_without_rate"))

    expect(legs(run)).to eq(%w[QRST])
    expect(run.stderr).to include("skipped ZZZZ").and include("no rate in the feed")
  end
end
