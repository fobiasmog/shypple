# frozen_string_literal: true

RSpec.describe Shypple::Sailing do
  describe "#quotable?" do
    it "is true when the sailing has a rate" do
      expect(sailing("ABCD", "CNSHA", "NLRTM", "2022-02-01", "2022-03-01")).to be_quotable
    end

    it "is false when the sailing has no rate" do
      unquoted = sailing("ZZZZ", "CNSHA", "NLRTM", "2022-02-01", "2022-03-01", rate: nil, currency: nil)

      expect(unquoted).not_to be_quotable
    end
  end

  it "is immutable" do
    expect { sailing("ABCD", "CNSHA", "NLRTM", "2022-02-01", "2022-03-01").instance_variable_set(:@rate, "1") }
      .to raise_error(FrozenError)
  end
end
