# Shypple sailing route finder

A small Ruby CLI that answers route questions from the MapReduce feed
(`response.json`). It finds:

- `cheapest-direct`: the cheapest single sailing (PLS-0001);
- `cheapest`: the cheapest route, direct or with any number of legs (WRT-0002);
- `fastest`: the fastest route, direct or with any number of legs (TST-0003).

Searches that have no answer yet are saved, and the user is told once a newer
feed can answer them (SLD-0004).

Read [`assumptions.md`](assumptions.md) for every rule the code follows, the
persistence trade-offs, and the open questions for the PO.

## Prerequisites

Docker with the compose plugin (`docker compose`). Nothing else is needed: Ruby,
the gems and Redis all run in containers.

## Build

```sh
docker compose build
```

## Run

The input is three lines on stdin: origin port, destination port, criterion
(`cheapest-direct`, `cheapest` or `fastest`). Case and surrounding spaces don't
matter.

Piped input (`-T` is required when stdin is a pipe or a file):

```sh
printf 'CNSHA\nNLRTM\ncheapest\n' | docker compose run --rm -T app
docker compose run --rm -T app < input.txt
```

Interactive input: type the three lines and the answer comes right after the
third one.

```sh
docker compose run --rm app
```

stdout carries only the result, a JSON array of legs (`[]` when there is no
route), so it can be piped straight into other tools. Warnings, saved-search
messages and errors go to stderr; add `2>/dev/null` to hide them. The exit
status is `0` when a result was printed and `1` for invalid input or an
unreadable feed.

Redis starts automatically with the first run and keeps running. To stop it,
run `docker compose down`; saved searches are kept.

## Tests

```sh
docker compose run --rm --entrypoint bundle app exec rspec
```

This runs the whole suite in the app image against the compose Redis and prints
line and branch coverage (the minimum is 95%). The Redis specs use database 15
and flush it, so saved searches in database 0 are never touched.

With Ruby 3.4 installed locally, `bundle install && bundle exec rspec` also
works. The Redis specs are skipped, with a message, when Redis isn't reachable
at `REDIS_URL`. Run `bundle exec rubocop` for the style check.

## Supplying a new feed

The feed is read again on every run. `./response.json` is bind-mounted into
the container read-only, so replacing that file is enough: no rebuild, and
saved searches are re-checked against it on the next run.

To use a file somewhere else, mount it and point `FEED_PATH` at it:

```sh
docker compose run --rm -T \
  -v "$PWD/new-feed.json:/app/feed.json:ro" -e FEED_PATH=/app/feed.json \
  app < input.txt
```

## Saved searches

A search with an empty result is saved in Redis (sorted set
`route_finder:saved_searches`, database 0). At the start of every run, saved
searches are re-evaluated against the current feed. Each one that now has a
route is written to stderr once, as a header line followed by the route JSON,
and then removed.

Redis data is bind-mounted to `./data/redis` on the host, so it survives
`docker compose down` (even with `-v`) and removal of containers and images.

```sh
# list saved searches with their save times (epoch seconds)
docker compose exec redis redis-cli ZRANGE route_finder:saved_searches 0 -1 WITHSCORES

# forget all saved searches
docker compose exec redis redis-cli DEL route_finder:saved_searches

# or wipe the Redis data completely (on Linux the folder belongs to the
# container's redis user, so rm may need sudo)
docker compose down && rm -rf data/redis
```

## Architecture

Twelve small files: one concept per file, no frameworks.

| File | Responsibility |
| --- | --- |
| `bin/route_finder` | Composition root: reads `FEED_PATH` and `REDIS_URL`, wires the real collaborators, exits with the CLI's status. |
| `lib/route_finder.rb` | Defines the `Shypple` namespace and requires the files below. |
| `lib/route_finder/sailing.rb` | `Sailing` value object: ports, dates, the feed's rate string and currency; `quotable?`. |
| `lib/route_finder/route.rb` | `Route` value object: ordered legs and `journey_days`, waiting in port included. |
| `lib/route_finder/query.rb` | `Query` value object: parses and validates the three stdin lines; `key` for storage. |
| `lib/route_finder/feed.rb` | Loads the JSON feed: sailings in feed order with their latest rate, exchange rates keyed by date. |
| `lib/route_finder/currency_converter.rb` | Converts a sailing's rate to EUR with the departure-date exchange rate (BigDecimal), or returns nil. |
| `lib/route_finder/criteria.rb` | `Cheapest` and `Fastest` strategies, and the registry mapping criterion names to them. |
| `lib/route_finder/route_finder.rb` | Depth-first search over valid routes in feed order; keeps the best eligible one and collects skipped sailings. |
| `lib/route_finder/saved_search_store.rb` | `RedisStore` and `MemoryStore` behind one three-method contract (`save`, `pending`, `remove`). |
| `lib/route_finder/presenter.rb` | Formats routes as the output JSON, and the saved-search notification. |
| `lib/route_finder/cli.rb` | Runs the steps of one run and decides what goes to stdout or stderr and which exit status to return. |

A run goes:

1. parse the query;
2. load the feed;
3. report saved searches that are now fulfilled;
4. answer the query on stdout;
5. save the query if its answer is empty.

The CLI receives its feed path, store and IO streams, so every behaviour is
tested in process with `StringIO` and `MemoryStore`. The `spec/` folder mirrors
`lib/`. `spec/integration/` drives the CLI with the sample feed and the small
fixture feeds in `spec/fixtures/`.

## Adding a criterion

A criterion is any object that answers four messages. `RouteFinder` relies on
nothing else, so it doesn't change when a criterion is added.

| Method | Returns |
| --- | --- |
| `max_legs` | `nil` for unlimited, or the maximum number of legs |
| `eligible?(sailing)` | Whether the sailing may appear in a route |
| `skip_reason(sailing)` | Why an ineligible sailing was left out; shown on stderr |
| `score(route)` | Any `Comparable`; lower is better, and ties go to the first route in feed order |

1. Add a class to `lib/route_finder/criteria.rb`, for example:

   ```ruby
   class FewestLegs
     def max_legs = nil
     def eligible?(sailing) = sailing.quotable?
     def skip_reason(_sailing) = NO_RATE
     def score(route) = route.legs.size
   end
   ```

2. Register it in `Criteria::BUILDERS`. Input validation picks up the new name
   from there:

   ```ruby
   "fewest-legs" => ->(_converter) { FewestLegs.new }
   ```

3. `spec/route_finder/criteria_spec.rb` already runs the shared
   `"a route criterion"` examples for every registered name. Add specs for the
   new scoring rule next to them.
