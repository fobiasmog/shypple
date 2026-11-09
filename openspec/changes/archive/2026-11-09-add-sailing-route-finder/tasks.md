## 1. Setup

- [x] 1.1 Run `git init` and add `.gitignore` (`data/`, `coverage/`, `.DS_Store`, `.bundle/`, `vendor/`). Commit the provided files (`CHALLENGE.md`, `response.json`, `assumptions.md`, `openspec/`) to `main`, then create and switch to `feature/sailing-route-finder`. Verify that `git branch --show-current` prints `feature/sailing-route-finder`.
- [x] 1.2 Add:
  - a `Gemfile` (Ruby 3.4; `redis`; test/dev: `rspec`, `simplecov`, `rubocop`);
  - `.rspec`;
  - `spec/spec_helper.rb`, which starts SimpleCov first with a 95% minimum line coverage;
  - a minimal `.rubocop.yml`;
  - `lib/route_finder.rb`.

  Verify that `bundle exec rspec` runs with 0 examples and no errors.
- [x] 1.3 Add a `Dockerfile` (`ruby:3.4-slim`, bundle install of all groups, copy the app and `response.json`, `ENTRYPOINT ["bin/route_finder"]`) and a `.dockerignore`. Add `docker-compose.yml` with:
  - `redis`: `redis:7.4-alpine`, `./data/redis:/data` bind mount, `redis-cli ping` healthcheck, no AOF;
  - `app`: `build: .`, `stdin_open: true`, `./response.json:/app/response.json:ro`, `REDIS_URL=redis://redis:6379/0`, `depends_on` redis `service_healthy`.

  Verify that `docker compose build` succeeds, that `docker compose run --rm --entrypoint bundle app exec rspec` runs in the container, and that `./data/redis` appears on the host.

## 2. Values, feed and currency

- [x] 2.1 Write specs first, then implement `Sailing`, `Route` and `Query` with `Data.define`, following design D2. Verify:
  - `quotable?` is false when there's no rate;
  - `journey_days` = 25 for a route with 10 days at sea and 15 days in port;
  - `Query#key` and `Query.from_key` round-trip;
  - `Query.parse` reads three lines from a StringIO that stays open, without blocking;
  - `Query.parse` normalizes ` cnsha ` / `Cheapest`;
  - `Query.parse` raises `Query::Invalid` for truncated input, a blank port, an unknown criterion (the message lists the supported ones), and origin equal to destination.
- [x] 2.2 Write specs first, then implement `Feed.load(path)` following design D3. Verify that:
  - the sample loads 9 sailings in feed order;
  - MNOP resolves to `812.00 USD`;
  - a fixture sailing with no rate has `rate: nil`;
  - exchange rates are BigDecimal;
  - a missing file and invalid JSON raise `Feed::Error` naming the path.
- [x] 2.3 Write specs first, then implement `CurrencyConverter#to_eur(sailing)` following design D4. Verify:
  - ABCD ≈ `523.357016`;
  - IJKL ≈ `742.78`;
  - an EUR sailing on a date with no exchange rates is returned unchanged;
  - nil for a missing date;
  - nil for a GBP sailing whose date has only usd/jpy.

## 3. Route search

- [x] 3.1 Write specs first (including a shared "criterion interface" example group), then implement `Criteria::Cheapest`, `Criteria::Fastest`, `Criteria.registry(converter)` and `Criteria::NAMES`, following design D5. Verify that:
  - Cheapest treats EUR legs as eligible even on dates with no exchange rates;
  - Cheapest treats legs with a missing exchange rate as ineligible, with a reason naming the currency and date;
  - Fastest ignores missing exchange rates but rejects legs with no rate;
  - `cheapest-direct` has `max_legs == 1`;
  - the shared group passes for all three registry entries.
- [x] 3.2 Write specs first, then implement `RouteFinder#find(origin, destination, criterion)` → `Result(route, skipped)`, following design D6. Verify:
  - on the sample feed: cheapest-direct → ABCD, cheapest → ERXQ+ETRG, fastest → QRST (17 days);
  - CNSHA→BRSSZ cheapest-direct → empty; NLRTM→CNSHA → empty;
  - connection rules: same-day transfer valid, departing before the previous arrival invalid;
  - A→B→A and A→X→B→X→C are never returned;
  - a three-leg fixture route is found;
  - equal-cost and equal-duration fixtures return the first route in feed order;
  - with no `2022-02-16` exchange rate, cheapest → ERXQ+ETRF with ETRG skipped exactly once, and fastest is unaffected;
  - ETRB is never reported for CNSHA→NLRTM.

## 4. Saved searches

- [x] 4.1 Write a shared store contract:
  - `save` is idempotent and keeps the first save time;
  - `pending` returns oldest first;
  - `remove` returns true once, then false.

  Implement `MemoryStore` and `RedisStore` (ZSET, `ZADD NX`, `ZRANGE`, `ZREM`, connection errors raised as `SavedSearchStore::Unavailable`) following design D7. The Redis contract uses database 15, flushed per example, tagged `:redis` and skipped with a message when Redis is unreachable. Verify that the contract passes for both stores in Docker, and that pointing `RedisStore` at a closed port raises `Unavailable`.

## 5. CLI

- [x] 5.1 Write specs first, then implement `Presenter#render(route)` and `#notification(query, route)` following design D9. Verify that:
  - the sample cheapest output exactly matches the cli spec example (ERXQ arrival `2022-02-12`);
  - IJKL renders `"97453"` / `"JPY"`;
  - an empty result renders `[]`;
  - the notification starts with `Saved search now available: NLRTM -> CNSHA (cheapest)`.
- [x] 5.2 Write specs first, then implement `CLI#run` with the step sequence and error handling from design D9. Verify with StringIO and `MemoryStore` that:
  - stdout is only JSON;
  - warnings, confirmations and notifications go to stderr;
  - invalid input → status 1 with no side effects;
  - feed error → status 1 with the store untouched;
  - a store raising `Unavailable` → status 0 with a warning;
  - an empty result is saved and confirmed;
  - a fulfilled saved search is notified once and removed.
- [x] 5.3 Implement `bin/route_finder` (reads `FEED_PATH` and `REDIS_URL`, builds `RedisStore`, `exit CLI.new(...).run`) and make it executable. Verify that `printf 'CNSHA\nNLRTM\ncheapest\n' | docker compose run --rm -T app` prints the ERXQ+ETRG JSON.

## 6. Integration and end-to-end checks

- [x] 6.1 Add `spec/integration/` specs that drive `CLI` with the real feed and fixtures:
  - all three criteria on the sample feed; the fastest spec's description explains the difference from the CHALLENGE.md example;
  - the saved-search lifecycle:
    1. NLRTM→CNSHA → `[]` and the search is saved;
    2. a fixture feed with NLRTM→CNSHA → notification, and the search is removed;
    3. a third run → silent;
  - a stdin search that matches a saved search fulfilled in the same run.

  Verify that all pass and coverage is at least 95%.
- [x] 6.2 Check end to end in Docker:
  - each criterion through a piped run;
  - an interactive run answers after the third line;
  - save a search, run `docker compose down`, swap in a feed with the route, run again, and see the notification on stderr;
  - the test suite is green in the container.

  Record the commands and outcomes in the final commit message.

## 7. Documentation and delivery

- [x] 7.1 Update `assumptions.md`:
  - fix #4 (previous arrival ≤ next departure, so a same-day transfer is allowed);
  - fix #6 (A→B→A never possible);
  - narrow #10 to cost criteria (return the cheapest of the remaining routes, warn on stderr, fastest unaffected, EUR exempt);
  - add: a sailing with no rate is excluded everywhere;
  - add: warnings only for sailings relevant to the search;
  - add: Redis with a bind mount and no AOF;
  - add: the feed is read on every run;
  - add: saved searches are re-evaluated first and notified once on stderr;
  - add: single user, searches deduplicated by origin, destination and criterion;
  - add the persistence trade-offs considered;
  - add a **Questions for the PO** section, each question naming the affected ticket.

  Verify that every rule covered by a spec traces back to an entry.
- [x] 7.2 Write `README.md`:
  - prerequisites (Docker only);
  - build, run (piped and interactive) and test commands;
  - how to supply a new feed;
  - where saved searches are stored and how to reset them;
  - a short architecture overview (one line per lib file);
  - how to add a criterion;
  - a link to `assumptions.md`.

  Verify by following it from a clean checkout.
- [x] 7.3 Run `bundle exec rubocop` and fix the offences. Commit all work on `feature/sailing-route-finder` and produce `git archive --format=zip -o shypple-route-finder.zip feature/sailing-route-finder`. Verify that the unzipped folder builds and answers a piped search.
