# frozen_string_literal: true

# The three-method contract the CLI relies on. Every store must pass it.
# Host groups provide `store`.
RSpec.shared_examples "a saved search store" do
  # "older" sorts after "newer" alphabetically, so only true save order can
  # put it first.
  let(:older) { Shypple::Query.new(origin: "NLRTM", destination: "CNSHA", criterion: "cheapest") }
  let(:newer) { Shypple::Query.new(origin: "CNSHA", destination: "BRSSZ", criterion: "cheapest-direct") }

  it "starts with nothing pending" do
    expect(store.pending).to eq([])
  end

  it "returns pending searches oldest first" do
    store.save(older)
    store.save(newer)

    expect(store.pending).to eq([older, newer])
  end

  it "saves a search once and keeps its first save time" do
    store.save(older)
    store.save(newer)
    store.save(older)

    expect(store.pending).to eq([older, newer])
  end

  it "keeps the same ports with another criterion as a separate search" do
    store.save(newer)
    store.save(newer.with(criterion: "cheapest"))

    expect(store.pending.map(&:criterion)).to eq(%w[cheapest-direct cheapest])
  end

  it "removes a search, returning true only the first time" do
    store.save(older)

    expect([store.remove(older), store.remove(older)]).to eq([true, false])
    expect(store.pending).to eq([])
  end

  it "returns false when removing a search that was never saved" do
    expect(store.remove(older)).to be(false)
  end
end
