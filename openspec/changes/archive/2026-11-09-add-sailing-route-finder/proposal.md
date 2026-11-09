## Why

Shypple finds shipping options by hand in Excel, and that won't scale. The MapReduce service already gives us every sailing, rate and EUR exchange rate as JSON (`response.json`). We need a small Ruby service that answers route questions from that feed: the cheapest direct sailing, the cheapest route, and the fastest route. It also has to remember searches that can't be answered yet and report them once a newer feed can answer them. This covers tickets PLS-0001, WRT-0002, TST-0003 and SLD-0004, all of which are required. The design must leave room for the announced DRY-0005 and TDD-0006 tickets.

## What Changes

- New Ruby CLI. It reads three lines from stdin (origin port, destination port, criteria) and writes the result to stdout as a JSON array of legs, in the format the challenge specifies.
- Loads the MapReduce feed from `response.json` on every run. The file is bind-mounted, and its path can be overridden with `FEED_PATH`. Data-quality rules applied while loading:
  - If the same `sailing_code` has more than one rate, the last one in the array wins.
  - Sailings with no rate entry are dropped and a warning is written to stderr.
  - A rate is converted to EUR using the exchange rate for the sailing's `departure_date`. EUR rates are never converted.
- Route search over the sailings, with any number of legs. A connection is valid when the previous leg's `arrival_date` is on or before the next leg's `departure_date`. No port may appear twice in a route, so A→B→A is never allowed.
- Three search criteria, set up so new ones can be added without touching existing code:
  - `cheapest-direct` (PLS-0001): the single direct sailing with the lowest EUR cost.
  - `cheapest` (WRT-0002): the direct or multi-leg route with the lowest total EUR cost.
  - `fastest` (TST-0003): the direct or multi-leg route with the shortest total journey time, measured from the first departure to the last arrival so waiting in port counts.
- Ties go to the first route found, walking sailings in feed order.
- A non-EUR sailing with no exchange rate for its departure date is left out of cost-based criteria, along with every route through it. The cheapest of the remaining routes is returned, and a stderr warning names each relevant sailing that was skipped. `fastest` is not affected.
- Saved searches (SLD-0004):
  - A search that returns an empty result is saved to Redis, keyed by `origin:destination:criteria`.
  - Every run first re-evaluates all saved searches against the current feed. Those that now have a result are printed to stderr and removed, so each is reported only once.
- Docker setup: a `Dockerfile` for the app and a `docker-compose.yml` with a Redis service. Redis data is bind-mounted to `./data/redis` and uses the default snapshots only, with no append-only log.
- Documentation: `assumptions.md` is completed with all agreed assumptions, the persistence trade-offs and a "Questions for the PO" section. A README covers how to build, run and test.
- Project hygiene: a git repository with one feature branch, and an RSpec suite with coverage reporting.

## Capabilities

### New Capabilities
- `sailing-feed`: Loads and normalizes the MapReduce JSON feed. Covers resolving duplicate rates, excluding sailings with no rate, looking up exchange rates by departure date, and converting to EUR, including EUR passthrough and reporting missing exchange rates.
- `route-search`: Builds valid direct and multi-leg routes (connection rule, no repeated ports, unlimited legs). Picks the best route for `cheapest-direct`, `cheapest` and `fastest`, with deterministic tie-breaking, and leaves routes that can't be priced out of cost criteria.
- `saved-searches`: Saves searches with no result, re-evaluates them against each new feed, reports fulfilled ones once and removes them. Storage is Redis, behind a small store interface.
- `cli`: The stdin/stdout contract (three input lines, a JSON leg array as output), stderr for warnings and notifications, the order of steps within a run, configuration through environment variables, and running under Docker / docker-compose.

### Modified Capabilities
<!-- None: greenfield project, no existing specs. -->

## Impact

- **New code**: everything is new. A deliberately small, flat Ruby app (about 12 files, about 400 lines of app code): value objects, feed loader, currency converter, route finder, criteria strategies, saved-search stores, presenter, CLI. Plus an RSpec suite.
- **Dependencies**:
  - Ruby 3.4 (official Docker image).
  - Gems: `redis` (client), `rspec`, `simplecov`, `rubocop` (dev).
  - Standard library only for JSON, BigDecimal and Date.
- **Infrastructure**:
  - Docker and docker-compose only, which is all the challenge allows us to assume.
  - A Redis 7 container.
  - Bind mounts for `./response.json` and `./data/redis`.
- **Interface**:
  - stdout carries only the result format the spec defines.
  - Warnings and saved-search notifications go to stderr.
  - The `fastest` result for the sample feed (QRST, direct, 17 days) deliberately differs from the illustrative CHALLENGE.md example. The definition of journey time we agreed on gives that result.
- **Docs**: `assumptions.md` (updated and extended) and a new `README.md`.
