## Context

This is a greenfield project. The folder holds `CHALLENGE.md`, the sample feed `response.json`, a draft `assumptions.md` and the OpenSpec scaffolding. It has no code and no git repository yet. For motivation see proposal.md (Why); for behaviour see `specs/` (sailing-feed, route-search, saved-searches, cli).

Constraints that shape the design:
- **Runtime:** Ruby only. Docker (with compose) is the only thing reviewers will have installed.
- **I/O:** the challenge fixes the stdin/stdout contract.
- **Grading:** OO design, SOLID, DRY and test coverage.
- **Scope:** this is interview homework. It has to be explained live, so the codebase should stay small: about 12 app files and about 400 lines of app code. Avoid layers that exist only to look "architectural".

## Goals / Non-Goals

**Goals:**
- A small, flat codebase where each file has one clear job and can be explained in a sentence.
- Adding a search criterion means one new class plus one registry entry, with no change to the route finder.
- The CLI receives its collaborators (feed path, store, IO streams), so every behaviour can be tested in-process without Docker.
- Deterministic output for the same feed and input.

**Non-Goals:**
- No HTTP API, daemon, background worker or user accounts.
- No speed optimizations for very large feeds (see Risks).
- No abstract base classes, service objects, or interfaces with only one implementation.
- No Rails, ActiveSupport or ORM.

## Decisions

### D1. Flat structure, one concept per file
```
bin/route_finder            # composition root: env vars, Redis, exit CLI#run
lib/route_finder.rb         # requires
lib/route_finder/
  sailing.rb                # value object
  route.rb                  # value object
  query.rb                  # value object + parsing/validation of stdin
  feed.rb                   # JSON → sailings + exchange rates
  currency_converter.rb     # sailing → EUR amount or nil
  route_finder.rb           # route search + best-route selection
  criteria.rb               # Cheapest, Fastest, registry
  saved_search_store.rb     # RedisStore, MemoryStore, Unavailable error
  presenter.rb              # JSON output + notification text
  cli.rb                    # run sequence, stderr, exit codes
spec/                       # mirrors lib/ + spec/integration/ + spec/fixtures/
```
*Why:* about 12 files is small enough to read in one sitting, and every file still has a single responsibility. *Alternative considered:* layered folders (domain/feed/search/criteria/cli) with roughly 25 files: separate `Money`, `ExchangeRateTable`, `RouteEnumerator`, `RouteSelector`, `Reevaluator`, `NullRepository` and `InputParser` classes. That's about 700 lines, and a lot of it would be indirection with nothing to justify it at this size.

### D2. Immutable value objects built with `Data.define`
- `Sailing`: origin, destination, departure/arrival `Date`, code, `rate` (original string or nil), `currency` (or nil), `quotable?`.
- `Route`: ordered `legs`, `departure_date`, `arrival_date`, `journey_days` (last arrival minus first departure, so waiting time counts; assumption #8).
- `Query`: origin, destination, criterion, `key` (`"CNSHA:NLRTM:cheapest"`), `Query.from_key`. `Query.parse(io, criteria_names)` reads exactly three lines with `gets`, so an interactive run doesn't wait for end of input. It strips the lines, normalizes case, and raises `Query::Invalid` for truncated input, a blank port, an unknown criterion, or origin equal to destination.

*Why:* `Data` gives immutability and equality for free. Validation lives on `Query` because it's about what makes a valid query, so it doesn't need a separate parser class. Keeping the rate as the original string lets stdout echo the feed exactly (`"97453"`).

### D3. `Feed` normalizes data but leaves eligibility to the criteria
`Feed.load(path)` parses JSON with `decimal_class: BigDecimal`, so exchange rates are never floats. It builds a `sailing_code → rate` index by walking `rates` in order, so the **last entry wins** (assumption #3). It returns `Feed(sailings, exchange_rates)`, with sailings in feed order and `rate: nil` when no rate exists. A missing file or invalid JSON raises `Feed::Error`, which names the path.
*Why:* whether a sailing can be used depends on the criterion: a missing exchange rate matters for cost but not for speed. Filtering at load time would wrongly drop sailings from `fastest`.

### D4. `CurrencyConverter#to_eur(sailing)` returns a BigDecimal or nil
EUR → `BigDecimal(rate)` with no lookup. Any other currency → `BigDecimal(rate) / exchange_rates.dig(departure_date, currency.downcase)`. A missing date or currency → nil.
*Why:* this is the only place that knows the exchange-rate rules (date-based, EUR as base, EUR passthrough). It's about 20 lines and simple to test.

### D5. Criteria are small classes behind a duck-typed interface, plus a registry
Every criterion responds to `max_legs` (nil means unlimited), `eligible?(sailing)`, `skip_reason(sailing)` and `score(route)` (lower is better).
- `Criteria::Cheapest.new(converter, max_legs: nil)`: eligible when the sailing is quotable and `to_eur` returns a value; the score is the sum of the EUR amounts.
- `Criteria::Fastest.new`: eligible when the sailing is quotable; the score is `route.journey_days`.
- `Criteria.registry(converter)` returns `{ "cheapest-direct" => Cheapest.new(converter, max_legs: 1), "cheapest" => Cheapest.new(converter), "fastest" => Fastest.new }`. `Criteria::NAMES` lists the supported names for input validation.

*Why:* this is the Strategy pattern without a base class. `cheapest-direct` reuses `Cheapest` with a one-leg limit, so cost logic exists once (DRY). A new criterion is one class and one hash entry, and `RouteFinder` doesn't change (open/closed). An RSpec shared example group checks that every criterion follows the interface, so there's no abstract class to maintain.

### D6. `RouteFinder` searches depth-first in feed order and keeps the first best route
`RouteFinder.new(sailings)` indexes sailings by origin port, keeping feed order. `#find(origin, destination, criterion)` → `Result(route, skipped)`:
1. A depth-first search yields every valid path. It tracks visited ports, so no port appears twice (assumption #5). A connection is valid when `prev.arrival_date <= next.departure_date` (assumption #4). It respects `criterion.max_legs`.
2. A path containing a leg where `eligible?` is false is set aside, and its bad legs are added to `skipped`: unique sailings with `skip_reason`, so only sailings relevant to this search are reported.
3. Eligible paths are reduced with a **strict `<`** on `score`, so the first route found wins ties (assumption #9).

*Why:* a depth-first search that walks sailings in feed order produces routes in exactly the tie order we defined, so no extra sort key is needed. Search and selection share one small class because they're one job ("best route for this query") of about 60 lines. The explicit strict comparison makes tie behaviour visible and testable, instead of relying on how `min_by` happens to break ties.

### D7. Saved-search stores share one three-method interface
`save(query)` (idempotent, keeps the first save time), `pending` (oldest first) and `remove(query)` (true only for the caller that removed it).
- `RedisStore.new(redis, key: "route_finder:saved_searches")` uses a ZSET of `query.key` scored by the epoch time it was saved:
  - `ZADD NX` makes `save` idempotent and keeps the original time.
  - `ZRANGE 0 -1` returns searches oldest first.
  - `ZREM` returns 1 only once, so concurrent runs notify exactly once.
  - Redis connection errors are re-raised as `SavedSearchStore::Unavailable`.
- `MemoryStore`: an ordered hash, used by the CLI and integration specs.

A shared contract spec runs against both stores.
*Why:* the CLI depends only on the three methods and on `Unavailable`, so it never references Redis (dependency inversion). `MemoryStore` isn't extra architecture: it's the test double and costs about 15 lines.

### D8. Redis persistence: bind mount, default snapshots
Compose service `redis:7.4-alpine` with `./data/redis:/data` bind-mounted, no AOF, and a `redis-cli ping` healthcheck. The app uses `depends_on: condition: service_healthy`.
*Why:* this was the user's decision. Data lives as plain files on the host, so it survives `down -v`, container removal and image removal. A graceful stop takes a snapshot. Losing recent saves after a crash is accepted, because the user can repeat the search. *Alternative considered:* a named volume, which `down -v` and `volume prune` delete.

### D9. `CLI#run` orchestrates; `Presenter` formats
`CLI.new(feed_path:, store:, stdin:, stdout:, stderr:)#run` returns the exit status. The steps are:
1. `Query.parse`. On `Query::Invalid`: stderr message, return 1.
2. `Feed.load`. On `Feed::Error`: stderr message, return 1, store untouched.
3. Build the converter, the registry and a `RouteFinder`.
4. **Notify about fulfilled searches**: for each `store.pending`, run `find`. If a route exists and `store.remove` is true, write `presenter.notification(query, route)` to stderr.
5. `find` the stdin query and write a warning to stderr for each skipped sailing.
6. Write `presenter.render(route)` to stdout.
7. If the result is empty, `store.save` and confirm on stderr.
8. Return 0.

`SavedSearchStore::Unavailable` in steps 4 or 7 → stderr warning, and the run continues.

`Presenter#render(route)` → `JSON.pretty_generate` with keys in the spec order (`[]` when empty). `#notification(query, route)` → `"Saved search now available: ORIG -> DEST (criterion)\n"` followed by the rendered JSON. Both use the same leg hash, so the format is defined once.

`bin/route_finder` reads `FEED_PATH` (default `/app/response.json`) and `REDIS_URL`, builds `RedisStore`, and calls `exit CLI.new(...).run`.
*Why:* re-checking saved searches takes about 8 lines, so it doesn't need its own class. Injected IO lets every cli and saved-searches spec run with `StringIO` and `MemoryStore`.

### D10. Docker
- **Dockerfile:** `ruby:3.4-slim`, `bundle install` (all groups, so one image runs the app and the tests), copy the app and the default `response.json`, `ENTRYPOINT ["bin/route_finder"]`.
- **Compose `app` service:** `stdin_open: true`, a bind mount `./response.json:/app/response.json:ro` (each `run` creates a fresh container, so a replaced file is picked up), `REDIS_URL=redis://redis:6379/0`.
- **Commands (in README):**
  - `docker compose build`
  - `docker compose run --rm -T app < input.txt` for piped input (`-T` is needed for redirection)
  - `docker compose run --rm app` for interactive use
  - `docker compose run --rm --entrypoint bundle app exec rspec` for the tests

### D11. Testing
- **Unit specs:** one per lib file. Expected values come from `response.json` plus `assumptions.md`, never from the CHALLENGE.md examples.
- **Shared examples:** a criterion interface group and a store contract group (`MemoryStore` and `RedisStore`). The Redis contract uses database 15, which it flushes, so saved searches in database 0 are never touched. It's tagged `:redis` and skipped with a message when Redis isn't reachable.
- **Integration specs:** drive `CLI` with `StringIO`, the sample feed and a few small fixture feeds in `spec/fixtures/`: missing exchange rate, a sailing without a rate, a three-leg route, an equal-score tie, and a "new feed" that fulfils a saved search.
- **Coverage:** SimpleCov with a 95% minimum line coverage. RuboCop is used for style, not as a gate.

## Risks / Trade-offs

- **The depth-first search enumerates every simple path, which grows exponentially with feed size** → Fine for payloads the size of the sample, because the time ordering and the no-port-twice rule prune heavily. `RouteFinder#find` is the only entry point, so we can later add branch-and-bound or a time-dependent Dijkstra without touching callers.
- **The `fastest` result differs from the CHALLENGE.md example** (QRST rather than ERXQ+ETRG) → This is deliberate and follows assumption #8. It's documented in `assumptions.md`, raised as a PO question, and covered by a spec whose description explains it.
- **"Last rate wins" depends on feed order** → Documented and raised with the PO. The policy lives in one loop in `Feed`.
- **The cheapest answer can hide a cheaper option that couldn't be priced** → This is agreed behaviour, and every excluded sailing is named on stderr.
- **Redis is an extra moving part** → The compose healthcheck handles start-up order. If Redis is unavailable, the search still answers.
- **No AOF, so a Redis crash can lose recent saves** → Accepted.
- **Every run re-evaluates all saved searches** → Fine at current scale. Later we can store a feed checksum and skip the re-check when the feed hasn't changed.
- **Port-code typos get saved indefinitely** → Accepted. A TTL on saved searches is a possible follow-up.

## Migration Plan

Greenfield. Delivery:
1. `git init`, commit the provided files on `main`, and do all work on one branch, `feature/sailing-route-finder`.
2. The Docker build and the test suite must pass.
3. Create the submission zip with `git archive`, which leaves out `data/` and `coverage/` via `.gitignore`.

## Open Questions

- Duplicate entries in `sailings` (the same code twice) don't occur in the sample. For now they're treated as separate sailings, which is harmless because ties resolve to the first. To raise with the PO; no design change needed.
- Whether `openspec/` and `.claude/` go in the submission zip. This is decided at packaging time.
