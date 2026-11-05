# frozen_string_literal: true

# SLD-0004 end to end: an unanswerable search is saved, a later feed fulfils
# it, the user is told once on stderr, and the search is forgotten.
RSpec.describe "Saved searches" do
  let(:new_feed) { fixture_path("new_feed") }

  shared_examples "the saved-search lifecycle" do
    it "saves an unanswered search, reports it once a new feed answers it, then stays silent" do
      saved = run_cli("NLRTM\nCNSHA\ncheapest\n", store:)
      expect(saved.stdout).to eq("[]\n")
      expect(saved.stderr).to start_with("No route found for NLRTM -> CNSHA (cheapest). Search saved")

      fulfilled = run_cli("CNSHA\nNLRTM\ncheapest\n", store:, feed: new_feed)
      expect(fulfilled.stderr).to start_with("Saved search now available: NLRTM -> CNSHA (cheapest)\n")
      expect(JSON.parse(fulfilled.stderr.lines.drop(1).join).map { |leg| leg["sailing_code"] }).to eq(%w[NRCN])
      expect(JSON.parse(fulfilled.stdout).map { |leg| leg["sailing_code"] }).to eq(%w[ERXQ ETRG])
      expect(store.pending).to be_empty

      silent = run_cli("CNSHA\nNLRTM\ncheapest\n", store:, feed: new_feed)
      expect(silent.stderr).to eq("")
    end

    it "saves the same search once, and the same ports with another criterion separately" do
      2.times { run_cli("CNSHA\nBRSSZ\ncheapest-direct\n", store:) }
      run_cli("NLRTM\nCNSHA\ncheapest\n", store:)

      expect(store.pending.map(&:key)).to eq(%w[CNSHA:BRSSZ:cheapest-direct NLRTM:CNSHA:cheapest])
    end

    it "reports several fulfilled searches oldest first" do
      run_cli("NLRTM\nCNSHA\ncheapest\n", store:)
      run_cli("CNSHA\nBRSSZ\ncheapest-direct\n", store:)

      run = run_cli("CNSHA\nNLRTM\nfastest\n", store:, feed: new_feed)

      expect(run.stderr.lines.grep(/^Saved search/)).to eq(
        [
          "Saved search now available: NLRTM -> CNSHA (cheapest)\n",
          "Saved search now available: CNSHA -> BRSSZ (cheapest-direct)\n"
        ]
      )
    end

    it "answers a stdin search that matches a saved search fulfilled in the same run, and forgets it" do
      run_cli("NLRTM\nCNSHA\ncheapest\n", store:)

      run = run_cli("NLRTM\nCNSHA\ncheapest\n", store:, feed: new_feed)

      expect(run.stderr).to start_with("Saved search now available: NLRTM -> CNSHA (cheapest)\n")
      expect(JSON.parse(run.stdout).map { |leg| leg["sailing_code"] }).to eq(%w[NRCN])
      expect(store.pending).to be_empty
    end
  end

  context "with the in-memory store" do
    let(:store) { Shypple::SavedSearchStore::MemoryStore.new }

    it_behaves_like "the saved-search lifecycle"
  end

  context "with Redis", :redis do
    let(:store) { Shypple::SavedSearchStore::RedisStore.new(RedisTestDatabase.client) }

    it_behaves_like "the saved-search lifecycle"
  end
end
