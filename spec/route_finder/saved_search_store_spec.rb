# frozen_string_literal: true

RSpec.describe Shypple::SavedSearchStore do
  describe Shypple::SavedSearchStore::MemoryStore do
    subject(:store) { described_class.new }

    it_behaves_like "a saved search store"
  end

  describe Shypple::SavedSearchStore::RedisStore do
    let(:query) { Shypple::Query.new(origin: "NLRTM", destination: "CNSHA", criterion: "cheapest") }

    context "with a reachable Redis", :redis do
      subject(:store) { described_class.new(RedisTestDatabase.client) }

      it_behaves_like "a saved search store"

      it "stores searches in one sorted set, scored by save time" do
        store.save(query)

        expect(RedisTestDatabase.client.zrange("route_finder:saved_searches", 0, -1)).to eq(["NLRTM:CNSHA:cheapest"])
      end

      it "never touches database 0" do
        expect(RedisTestDatabase.client.connection[:db]).to eq(15)
      end
    end

    context "when Redis can't be reached" do
      subject(:store) { described_class.new(Redis.new(url: "redis://127.0.0.1:1/0", reconnect_attempts: 0)) }

      it "raises Unavailable from every operation" do
        [-> { store.save(query) }, -> { store.pending }, -> { store.remove(query) }].each do |operation|
          expect(&operation).to raise_error(Shypple::SavedSearchStore::Unavailable, /127\.0\.0\.1:1/)
        end
      end
    end
  end
end
