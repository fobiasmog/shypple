# frozen_string_literal: true

# RouteFinder on small hand-built graphs, one shape per group. Ports are
# letters, sailing codes name their legs, and rates are EUR unless a group is
# about currencies. The comment at the top of each group sketches its graph.
RSpec.describe Shypple::RouteFinder, "on different graph shapes" do
  # 1 EUR = 2 USD = 100 JPY, except on 2022-01-02, when 1 EUR = 1.25 USD.
  # There are no GBP rates at all, and no rates on the other dates.
  let(:exchange_rates) do
    {
      Date.new(2022, 1, 1) => { "usd" => BigDecimal("2"), "jpy" => BigDecimal("100") },
      Date.new(2022, 1, 2) => { "usd" => BigDecimal("1.25") },
      Date.new(2022, 1, 4) => { "usd" => BigDecimal("2") },
      Date.new(2022, 1, 6) => { "jpy" => BigDecimal("100") }
    }
  end
  let(:criteria) { Shypple::Criteria.registry(Shypple::CurrencyConverter.new(exchange_rates)) }

  def on(day_offset) = (Date.new(2022, 1, 1) + day_offset).iso8601

  def search(sailings, origin, destination, criterion)
    criterion = criteria.fetch(criterion) if criterion.is_a?(String)
    described_class.new(sailings).find(origin, destination, criterion)
  end

  def route_codes(sailings, origin, destination, criterion)
    search(sailings, origin, destination, criterion).route&.legs&.map(&:code)
  end

  def candidates(sailings, origin, destination, max_legs: nil)
    recorder = RecordingCriterion.new(max_legs:)
    described_class.new(sailings).find(origin, destination, recorder)
    recorder.candidates
  end

  describe "a diamond: two branches that meet again" do
    # A -AB 100, 4d-> B -BD 100, 4d-> D   = 200 EUR, 9 days
    # A -AC 300, 2d-> C -CD 100, 2d-> D   = 400 EUR, 5 days
    let(:sailings) do
      [
        sailing("AB", "A", "B", "2022-01-01", "2022-01-05", rate: "100.00"),
        sailing("AC", "A", "C", "2022-01-01", "2022-01-03", rate: "300.00"),
        sailing("BD", "B", "D", "2022-01-06", "2022-01-10", rate: "100.00"),
        sailing("CD", "C", "D", "2022-01-04", "2022-01-06", rate: "100.00")
      ]
    end

    it "considers both branches, in feed order" do
      expect(candidates(sailings, "A", "D")).to eq([%w[AB BD], %w[AC CD]])
    end

    it "takes the cheaper branch for cheapest and the quicker one for fastest" do
      expect(route_codes(sailings, "A", "D", "cheapest")).to eq(%w[AB BD])
      expect(route_codes(sailings, "A", "D", "fastest")).to eq(%w[AC CD])
    end

    it "finds nothing for cheapest-direct" do
      expect(route_codes(sailings, "A", "D", "cheapest-direct")).to be_nil
    end
  end

  describe "a six-leg chain, listed in reverse feed order" do
    # P0 -> P1 -> P2 -> P3 -> P4 -> P5 -> P6: each leg 2 days at sea, then 1 day in port
    let(:sailings) do
      (0...6).map { |i| sailing("L#{i}", "P#{i}", "P#{i + 1}", on(3 * i), on((3 * i) + 2)) }.reverse
    end

    it "returns all six legs in travel order for cheapest and fastest" do
      expect(%w[cheapest fastest].map { |name| route_codes(sailings, "P0", "P6", name) })
        .to all(eq(%w[L0 L1 L2 L3 L4 L5]))
    end

    it "counts the whole journey, time in port included: 17 days" do
      expect(search(sailings, "P0", "P6", "fastest").route.journey_days).to eq(17)
    end

    it "finds a section of the chain between two intermediate ports" do
      expect(route_codes(sailings, "P2", "P5", "cheapest")).to eq(%w[L2 L3 L4])
    end

    it "finds nothing for cheapest-direct" do
      expect(route_codes(sailings, "P0", "P6", "cheapest-direct")).to be_nil
    end
  end

  describe "a cycle A -> B -> C -> A that can be sailed round in time, with an exit C -> D" do
    # AB1, BC, CA, AB2, BC2 connect one after another, so only the no-repeat rule
    # keeps A -> B -> C -> A -> B -> C -> D out.
    let(:sailings) do
      [
        sailing("AB1", "A", "B", "2022-01-01", "2022-01-02"),
        sailing("BC", "B", "C", "2022-01-03", "2022-01-04"),
        sailing("CA", "C", "A", "2022-01-05", "2022-01-06"),
        sailing("AB2", "A", "B", "2022-01-07", "2022-01-08"),
        sailing("BC2", "B", "C", "2022-01-09", "2022-01-10"),
        sailing("CD", "C", "D", "2022-01-11", "2022-01-12")
      ]
    end

    it "passes each port of the cycle once on the way out (A to D)" do
      expect(candidates(sailings, "A", "D")).to eq([%w[AB1 BC CD], %w[AB1 BC2 CD], %w[AB2 BC2 CD]])
    end

    it "uses part of the cycle when that is the way there (C to B goes through A)" do
      expect(route_codes(sailings, "C", "B", "fastest")).to eq(%w[CA AB2])
    end
  end

  describe "two disconnected parts: A -> B -> C and D -> E" do
    let(:sailings) do
      [
        sailing("AB", "A", "B", "2022-01-01", "2022-01-02"),
        sailing("BC", "B", "C", "2022-01-03", "2022-01-04"),
        sailing("DE", "D", "E", "2022-01-01", "2022-01-02")
      ]
    end

    it "finds no route between the parts and reports nothing" do
      expect(search(sailings, "A", "E", "cheapest")).to have_attributes(route: nil, skipped: {})
    end

    it "finds no route to a port that no sailing reaches" do
      expect(route_codes(sailings, "A", "Z", "fastest")).to be_nil
    end

    it "finds no route against the direction of the sailings (C to A)" do
      expect(route_codes(sailings, "C", "A", "fastest")).to be_nil
    end
  end

  describe "dead-end branches beside the one way through" do
    # A -> X1 (nothing leaves X1); A -> X2 -> X3 (nothing leaves X3); A -> B -> D
    let(:sailings) do
      [
        sailing("AX1", "A", "X1", "2022-01-01", "2022-01-02"),
        sailing("AX2", "A", "X2", "2022-01-01", "2022-01-02"),
        sailing("X2X3", "X2", "X3", "2022-01-03", "2022-01-04"),
        sailing("AB", "A", "B", "2022-01-01", "2022-01-02"),
        sailing("BD", "B", "D", "2022-01-03", "2022-01-04")
      ]
    end

    it "yields only the branch that reaches the destination" do
      expect(candidates(sailings, "A", "D")).to eq([%w[AB BD]])
    end
  end

  describe "sailings that carry on past the destination" do
    # A -> D directly (500 EUR); D -> E -> D beyond it; A -> E -> D (2 EUR)
    let(:sailings) do
      [
        sailing("AD", "A", "D", "2022-01-01", "2022-01-02", rate: "500.00"),
        sailing("DE", "D", "E", "2022-01-03", "2022-01-04", rate: "1.00"),
        sailing("AE", "A", "E", "2022-01-01", "2022-01-03", rate: "1.00"),
        sailing("ED", "E", "D", "2022-01-05", "2022-01-06", rate: "1.00")
      ]
    end

    it "stops at the destination instead of passing through it" do
      expect(candidates(sailings, "A", "D")).to eq([%w[AD], %w[AE ED]])
    end

    it "takes A -> E -> D as cheapest" do
      expect(route_codes(sailings, "A", "D", "cheapest")).to eq(%w[AE ED])
    end
  end

  describe "parallel sailings: three A -> B and two B -> C" do
    # AB3 arrives 01-07, after BC1 has left on 01-04, so AB3 can only take BC2
    let(:sailings) do
      [
        sailing("AB1", "A", "B", "2022-01-01", "2022-01-03"),
        sailing("AB2", "A", "B", "2022-01-02", "2022-01-04"),
        sailing("AB3", "A", "B", "2022-01-05", "2022-01-07", rate: "50.00"),
        sailing("BC1", "B", "C", "2022-01-04", "2022-01-06"),
        sailing("BC2", "B", "C", "2022-01-08", "2022-01-09", rate: "50.00")
      ]
    end

    it "pairs every first leg with each second leg it can still catch" do
      expect(candidates(sailings, "A", "C"))
        .to eq([%w[AB1 BC1], %w[AB1 BC2], %w[AB2 BC1], %w[AB2 BC2], %w[AB3 BC2]])
    end

    it "takes the cheapest pairing (100 EUR)" do
      expect(route_codes(sailings, "A", "C", "cheapest")).to eq(%w[AB3 BC2])
    end

    it "breaks the 4-day tie for fastest in feed order: AB2 -> BC1 before AB3 -> BC2" do
      expect(route_codes(sailings, "A", "C", "fastest")).to eq(%w[AB2 BC1])
    end
  end

  describe "waiting in port for a cheaper onward sailing" do
    # A -AB-> B, then FAST on to C at once (500 EUR) or SLOW two weeks later (50 EUR)
    let(:sailings) do
      [
        sailing("AB", "A", "B", "2022-01-01", "2022-01-03"),
        sailing("FAST", "B", "C", "2022-01-04", "2022-01-06", rate: "500.00"),
        sailing("SLOW", "B", "C", "2022-01-20", "2022-01-22", rate: "50.00")
      ]
    end

    it "waits for SLOW when cheapest" do
      expect(route_codes(sailings, "A", "C", "cheapest")).to eq(%w[AB SLOW])
    end

    it "takes FAST when fastest" do
      expect(route_codes(sailings, "A", "C", "fastest")).to eq(%w[AB FAST])
    end
  end

  describe "a later sailing with a shorter voyage" do
    # EARLY A -> B: 01-01 to 01-20 (19 days); LATE A -> B: 01-10 to 01-25 (15 days)
    let(:sailings) do
      [
        sailing("EARLY", "A", "B", "2022-01-01", "2022-01-20"),
        sailing("LATE", "A", "B", "2022-01-10", "2022-01-25")
      ]
    end

    it "is fastest although it arrives later: journey time counts, not the arrival date" do
      expect(route_codes(sailings, "A", "B", "fastest")).to eq(%w[LATE])
    end
  end

  describe "a two-leg route with a long wait in port" do
    # DIRECT A -> C: 20 days at sea, 900 EUR
    # AB + BC: 10 days at sea plus 15 days waiting in B = 25 days, 200 EUR
    let(:sailings) do
      [
        sailing("DIRECT", "A", "C", "2022-01-01", "2022-01-21", rate: "900.00"),
        sailing("AB", "A", "B", "2022-01-01", "2022-01-06"),
        sailing("BC", "B", "C", "2022-01-21", "2022-01-26")
      ]
    end

    it "loses to the direct sailing on fastest, because waiting counts" do
      expect(route_codes(sailings, "A", "C", "fastest")).to eq(%w[DIRECT])
    end

    it "wins on cheapest, at 25 days door to door" do
      route = search(sailings, "A", "C", "cheapest").route

      expect([route.legs.map(&:code), route.journey_days]).to eq([%w[AB BC], 25])
    end
  end

  describe "direct sailings quoted in different currencies" do
    # all depart 2022-01-01: 10000 JPY = 100 EUR, 150 EUR, 180 USD = 90 EUR
    let(:sailings) do
      [
        sailing("YEN1", "A", "B", "2022-01-01", "2022-01-10", rate: "10000", currency: "JPY"),
        sailing("EUR1", "A", "B", "2022-01-01", "2022-01-10", rate: "150.00", currency: "EUR"),
        sailing("USD1", "A", "B", "2022-01-01", "2022-01-10", rate: "180.00", currency: "USD")
      ]
    end

    it "compares the EUR amounts, not the quoted numbers" do
      expect(route_codes(sailings, "A", "B", "cheapest-direct")).to eq(%w[USD1])
    end
  end

  describe "the same USD rate on two departure dates" do
    # 100 USD departing 01-02 (1.25 USD per EUR) = 80 EUR; departing 01-01 (2 USD per EUR) = 50 EUR
    let(:sailings) do
      [
        sailing("JAN2", "A", "B", "2022-01-02", "2022-01-10", rate: "100.00", currency: "USD"),
        sailing("JAN1", "A", "B", "2022-01-01", "2022-01-10", rate: "100.00", currency: "USD")
      ]
    end

    it "prices each with its own departure date's exchange rate" do
      route = search(sailings, "A", "B", "cheapest-direct").route

      expect(route.legs.map(&:code)).to eq(%w[JAN1])
      expect(criteria.fetch("cheapest-direct").score(route)).to eq(BigDecimal("50"))
    end
  end

  describe "three legs in three currencies against a dearer direct sailing" do
    # A -AB 100 EUR-> B -BC 100 USD = 50 EUR-> C -CD 5000 JPY = 50 EUR-> D   = 200 EUR
    # A -DIRECT 210 EUR-> D
    let(:sailings) do
      [
        sailing("DIRECT", "A", "D", "2022-01-01", "2022-01-08", rate: "210.00"),
        sailing("AB", "A", "B", "2022-01-01", "2022-01-03", rate: "100.00"),
        sailing("BC", "B", "C", "2022-01-04", "2022-01-05", rate: "100.00", currency: "USD"),
        sailing("CD", "C", "D", "2022-01-06", "2022-01-08", rate: "5000", currency: "JPY")
      ]
    end

    it "adds the legs up in EUR and takes the three-leg route" do
      route = search(sailings, "A", "D", "cheapest").route

      expect(route.legs.map(&:code)).to eq(%w[AB BC CD])
      expect(criteria.fetch("cheapest").score(route)).to eq(BigDecimal("200"))
    end
  end

  describe "a leg that can't be priced, in the middle of a route" do
    # A -AB-> B -BC (GBP, no rate)-> C -CD-> D: 5 days
    # A -DIRECT 500 EUR-> D: 19 days
    let(:sailings) do
      [
        sailing("AB", "A", "B", "2022-01-01", "2022-01-02", rate: "10.00"),
        sailing("BC", "B", "C", "2022-01-03", "2022-01-04", rate: "10.00", currency: "GBP"),
        sailing("CD", "C", "D", "2022-01-05", "2022-01-06", rate: "10.00"),
        sailing("DIRECT", "A", "D", "2022-01-01", "2022-01-20", rate: "500.00")
      ]
    end

    it "falls back to the direct sailing for cheapest and names the middle leg" do
      result = search(sailings, "A", "D", "cheapest")

      expect(result.route.legs.map(&:code)).to eq(%w[DIRECT])
      expect(result.skipped.transform_keys(&:code)).to eq("BC" => "no GBP exchange rate for 2022-01-03")
    end

    it "keeps the three-leg route for fastest, with nothing skipped" do
      result = search(sailings, "A", "D", "fastest")

      expect([result.route.legs.map(&:code), result.skipped]).to eq([%w[AB BC CD], {}])
    end
  end

  describe "only unpriceable sailings" do
    # two GBP sailings A -> B, and no GBP exchange rates at all
    let(:sailings) do
      [
        sailing("G1", "A", "B", "2022-01-01", "2022-01-05", currency: "GBP"),
        sailing("G2", "A", "B", "2022-01-02", "2022-01-06", currency: "GBP")
      ]
    end

    it "returns no route for cheapest and names both sailings" do
      result = search(sailings, "A", "B", "cheapest")

      expect(result.route).to be_nil
      expect(result.skipped.transform_keys(&:code)).to eq(
        "G1" => "no GBP exchange rate for 2022-01-01",
        "G2" => "no GBP exchange rate for 2022-01-02"
      )
    end

    it "still answers fastest, taking the first of the two 4-day sailings" do
      expect(route_codes(sailings, "A", "B", "fastest")).to eq(%w[G1])
    end
  end

  describe "unpriceable sailings that lie on no valid route" do
    # AB arrives in B on 01-10, then BD goes on to D.
    # EARLY (GBP) leaves B on 01-05, before AB arrives; DEAD (GBP) goes to X, which nothing leaves.
    let(:sailings) do
      [
        sailing("AB", "A", "B", "2022-01-01", "2022-01-10"),
        sailing("EARLY", "B", "D", "2022-01-05", "2022-01-06", currency: "GBP"),
        sailing("DEAD", "B", "X", "2022-01-11", "2022-01-12", currency: "GBP"),
        sailing("BD", "B", "D", "2022-01-12", "2022-01-14")
      ]
    end

    it "doesn't report them" do
      result = search(sailings, "A", "D", "cheapest")

      expect([result.route.legs.map(&:code), result.skipped]).to eq([%w[AB BD], {}])
    end
  end

  describe "a limit of two legs" do
    # A -> B -> C -> D: 3 legs, 30 EUR; A -> X -> D: 2 legs, 100 EUR
    let(:sailings) do
      [
        sailing("AB", "A", "B", "2022-01-01", "2022-01-02", rate: "10.00"),
        sailing("BC", "B", "C", "2022-01-03", "2022-01-04", rate: "10.00"),
        sailing("CD", "C", "D", "2022-01-05", "2022-01-06", rate: "10.00"),
        sailing("AX", "A", "X", "2022-01-01", "2022-01-02", rate: "50.00"),
        sailing("XD", "X", "D", "2022-01-03", "2022-01-04", rate: "50.00")
      ]
    end

    it "takes the three-leg route when legs are unlimited" do
      expect(route_codes(sailings, "A", "D", "cheapest")).to eq(%w[AB BC CD])
    end

    it "takes the two-leg route when limited to two" do
      two_legs = Shypple::Criteria::Cheapest.new(Shypple::CurrencyConverter.new(exchange_rates), max_legs: 2)

      expect(route_codes(sailings, "A", "D", two_legs)).to eq(%w[AX XD])
    end

    it "never produces the three-leg candidate under the limit" do
      expect(candidates(sailings, "A", "D", max_legs: 2)).to eq([%w[AX XD]])
    end
  end

  describe "a chain broken at its last connection" do
    # A -> B -> C connect, but CD leaves C on 01-04, the day before BC arrives
    let(:sailings) do
      [
        sailing("AB", "A", "B", "2022-01-01", "2022-01-02"),
        sailing("BC", "B", "C", "2022-01-03", "2022-01-05"),
        sailing("CD", "C", "D", "2022-01-04", "2022-01-06")
      ]
    end

    it "has no candidate route at all" do
      expect(candidates(sailings, "A", "D")).to eq([])
    end
  end

  describe "a layered graph: 5 hops with 4 parallel sailings each (1,024 routes)" do
    # P0 => P1 => P2 => P3 => P4 => P5. Every sailing of a hop connects to every
    # sailing of the next. Sailing HhSs costs ((s + h) % 4 + 1) * 10 EUR, so the
    # cheapest one sits at a different position on each hop. All routes take 44 days.
    let(:sailings) do
      (0...5).flat_map do |hop|
        (0...4).map do |pick|
          sailing("H#{hop}S#{pick}", "P#{hop}", "P#{hop + 1}", on(10 * hop), on((10 * hop) + 4),
                  rate: "#{(((pick + hop) % 4) + 1) * 10}.00")
        end
      end
    end

    it "considers every combination" do
      expect(candidates(sailings, "P0", "P5").size).to eq(1024)
    end

    it "takes the cheapest sailing on every hop: 5 x 10 EUR" do
      route = search(sailings, "P0", "P5", "cheapest").route

      expect(route.legs.map(&:code)).to eq(%w[H0S0 H1S3 H2S2 H3S1 H4S0])
      expect(criteria.fetch("cheapest").score(route)).to eq(BigDecimal("50"))
    end

    it "breaks the 1,024-way tie for fastest with the first sailing of each hop" do
      expect(route_codes(sailings, "P0", "P5", "fastest")).to eq(%w[H0S0 H1S0 H2S0 H3S0 H4S0])
    end
  end
end
