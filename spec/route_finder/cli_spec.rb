# frozen_string_literal: true

RSpec.describe Shypple::CLI do
  let(:store) { Shypple::SavedSearchStore::MemoryStore.new }
  let(:unfulfilled) { Shypple::Query.new(origin: "NLRTM", destination: "CNSHA", criterion: "cheapest") }

  describe "a search with a result" do
    subject(:run) { run_cli("CNSHA\nNLRTM\ncheapest\n", store:) }

    it "prints the route as JSON on stdout and exits 0" do
      expect(run.status).to eq(0)
      expect(JSON.parse(run.stdout).map { |leg| leg["sailing_code"] }).to eq(%w[ERXQ ETRG])
    end

    it "writes nothing to stderr and saves nothing" do
      expect([run.stderr, store.pending]).to eq(["", []])
    end
  end

  describe "warnings" do
    subject(:run) { run_cli("CNSHA\nNLRTM\ncheapest\n", store:, feed: fixture_path("missing_exchange_rate")) }

    it "names each skipped sailing on stderr, keeping stdout pure JSON" do
      expect(run.stderr).to eq(
        "Warning: skipped ETRG (ESBCN -> NLRTM, departing 2022-02-16): no USD exchange rate for 2022-02-16\n"
      )
      expect(JSON.parse(run.stdout).map { |leg| leg["sailing_code"] }).to eq(%w[ERXQ ETRF])
    end
  end

  describe "a search without a result" do
    subject(:run) { run_cli("NLRTM\nCNSHA\ncheapest\n", store:) }

    it "prints [] on stdout and exits 0" do
      expect([run.status, run.stdout]).to eq([0, "[]\n"])
    end

    it "saves the search and confirms on stderr" do
      expect(run.stderr).to eq("No route found for NLRTM -> CNSHA (cheapest). " \
                               "Search saved; you will be notified when an option becomes available.\n")
      expect(store.pending).to eq([unfulfilled])
    end
  end

  describe "saved searches" do
    before { store.save(unfulfilled) }

    it "notifies a fulfilled saved search on stderr, once, and removes it" do
      first = run_cli("CNSHA\nNLRTM\nfastest\n", store:, feed: fixture_path("new_feed"))
      second = run_cli("CNSHA\nNLRTM\nfastest\n", store:, feed: fixture_path("new_feed"))

      expect(first.stderr).to start_with("Saved search now available: NLRTM -> CNSHA (cheapest)\n[\n")
      expect(first.stderr).to include('"sailing_code": "NRCN"')
      expect(JSON.parse(first.stdout).map { |leg| leg["sailing_code"] }).to eq(%w[QRST])
      expect([second.stderr, store.pending]).to eq(["", []])
    end

    it "keeps a still-unfulfilled saved search silently" do
      run = run_cli("CNSHA\nNLRTM\nfastest\n", store:)

      expect([run.stderr, store.pending]).to eq(["", [unfulfilled]])
    end
  end

  describe "invalid input" do
    subject(:run) { run_cli("CNSHA\nNLRTM\ncheapest-ever\n", store:) }

    it "exits 1 with the reason on stderr" do
      expect(run.status).to eq(1)
      expect(run.stderr)
        .to start_with("Error: Unknown criterion 'cheapest-ever'. Supported: cheapest-direct, cheapest, fastest")
    end

    it "has no side effects" do
      expect([run.stdout, store.pending]).to eq(["", []])
    end
  end

  describe "a feed that can't be loaded" do
    subject(:run) { run_cli("NLRTM\nCNSHA\ncheapest\n", store:, feed: "/missing/response.json") }

    before { store.save(unfulfilled) }

    it "exits 1, names the path on stderr and prints nothing on stdout" do
      expect([run.status, run.stdout]).to eq([1, ""])
      expect(run.stderr).to start_with("Error: Cannot load feed /missing/response.json")
    end

    it "leaves saved searches untouched" do
      run

      expect(store.pending).to eq([unfulfilled])
    end
  end

  describe "when saved-search storage is unavailable" do
    let(:store) { instance_double(Shypple::SavedSearchStore::RedisStore) }

    before do
      %i[pending save remove].each do |operation|
        allow(store).to receive(operation).and_raise(Shypple::SavedSearchStore::Unavailable, "Connection refused")
      end
    end

    it "still answers a fulfillable search and warns that saved searches weren't checked" do
      run = run_cli("CNSHA\nNLRTM\ncheapest\n", store:)

      expect(run.status).to eq(0)
      expect(JSON.parse(run.stdout)).not_to be_empty
      expect(run.stderr).to eq("Warning: saved searches could not be checked: Connection refused\n")
    end

    it "still answers an unfulfillable search and warns that it couldn't be saved" do
      run = run_cli("NLRTM\nCNSHA\ncheapest\n", store:)

      expect([run.status, run.stdout]).to eq([0, "[]\n"])
      expect(run.stderr).to end_with("Warning: the search could not be saved: Connection refused\n")
    end
  end
end
