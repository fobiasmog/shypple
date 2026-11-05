# frozen_string_literal: true

require "stringio"
require "timeout"

RSpec.describe Shypple::Query do
  let(:names) { %w[cheapest-direct cheapest fastest] }

  def parse(text) = described_class.parse(StringIO.new(text), names)

  describe "#key and .from_key" do
    let(:query) { described_class.new(origin: "CNSHA", destination: "NLRTM", criterion: "cheapest") }

    it "joins origin, destination and criterion" do
      expect(query.key).to eq("CNSHA:NLRTM:cheapest")
    end

    it "round-trips through the key" do
      expect(described_class.from_key(query.key)).to eq(query)
    end
  end

  it "describes itself for people" do
    expect(described_class.new(origin: "NLRTM", destination: "CNSHA", criterion: "cheapest").to_s)
      .to eq("NLRTM -> CNSHA (cheapest)")
  end

  describe ".parse" do
    it "reads origin, destination and criterion from three lines" do
      expect(parse("CNSHA\nNLRTM\ncheapest-direct\n"))
        .to eq(described_class.new(origin: "CNSHA", destination: "NLRTM", criterion: "cheapest-direct"))
    end

    it "strips whitespace, upper-cases ports and lower-cases the criterion" do
      expect(parse(" cnsha \nnlrtm\nCheapest\n"))
        .to eq(described_class.new(origin: "CNSHA", destination: "NLRTM", criterion: "cheapest"))
    end

    it "accepts a last line without a trailing newline" do
      expect(parse("CNSHA\nNLRTM\nfastest").criterion).to eq("fastest")
    end

    it "stops after the third line, leaving the rest of the stream unread" do
      io = StringIO.new("CNSHA\nNLRTM\ncheapest\nextra\n")
      described_class.parse(io, names)

      expect(io.read).to eq("extra\n")
    end

    it "answers without waiting for the input stream to close (interactive use)" do
      reader, writer = IO.pipe
      writer.write("CNSHA\nNLRTM\nfastest\n")

      query = Timeout.timeout(2) { described_class.parse(reader, names) }

      expect(query.criterion).to eq("fastest")
    ensure
      [reader, writer].each(&:close)
    end

    it "rejects truncated input" do
      expect { parse("CNSHA\nNLRTM\n") }.to raise_error(described_class::Invalid, /missing input/i)
    end

    it "rejects empty input" do
      expect { parse("") }.to raise_error(described_class::Invalid, /missing input/i)
    end

    it "rejects a blank origin port" do
      expect { parse("  \nNLRTM\ncheapest\n") }.to raise_error(described_class::Invalid, /origin port.*blank/i)
    end

    it "rejects a blank destination port" do
      expect { parse("CNSHA\n\ncheapest\n") }.to raise_error(described_class::Invalid, /destination port.*blank/i)
    end

    it "rejects an unknown criterion and lists the supported ones" do
      expect { parse("CNSHA\nNLRTM\ncheapest-ever\n") }
        .to raise_error(described_class::Invalid, /cheapest-ever.*cheapest-direct, cheapest, fastest/)
    end

    it "rejects the same origin and destination" do
      expect { parse("CNSHA\ncnsha\ncheapest\n") }
        .to raise_error(described_class::Invalid, /origin and destination must differ/i)
    end
  end
end
