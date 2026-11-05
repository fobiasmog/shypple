# Assumptions / Limitations

Expected results in the specs come from `response.json` and the rules below.
The examples in `CHALLENGE.md` only illustrate the input/output format.

## Pricing and route search

1. `exchange_rates` has at most one entry per date; dates don't repeat.
2. Exchange rates are EUR-based: `usd: 1.1138` means 1 EUR = 1.1138 USD, so
   the EUR amount is the rate divided by the exchange rate (usd→eur, jpy→eur,
   and so on). Currency codes match regardless of case (`USD` in a rate matches
   `usd` in the exchange rates).
3. `rates` runs from oldest to newest. When the same `sailing_code` has more
   than one rate, the last one in the array wins (MNOP → `812.00 USD`).
4. Legs connect only forward in time: the previous leg's `arrival_date` must be
   on or before the next leg's `departure_date`. A same-day transfer is
   allowed.
5. A route never passes through the same port twice. With A→B→C, A→X→C, B→X
   and X→B available, the trip A→X→B→X→C is not possible. This could change if
   port fees and limits on time in port are added later, but not now.
6. A route never returns to a port it has left, so A→B→A is never possible, on
   any dates.
7. Costs are calculated and compared in EUR, using the exchange rate for each
   sailing's `departure_date`.
8. Time waiting in port between legs counts as journey time: 10 days at sea plus
   15 days in port is a 25-day journey. `fastest` therefore measures from the
   first departure to the last arrival. On the sample feed this makes QRST
   (17 days) the fastest CNSHA→NLRTM route, not ERXQ+ETRG (22 days) as the
   illustrative `CHALLENGE.md` example shows.
9. When several routes tie on the requested criterion (same EUR cost, or same
   journey time for `fastest`), the first one wins. Routes are ordered by the
   positions of their legs in `sailings`: first legs are compared first, then
   second legs, and so on.
10. A non-EUR sailing with no exchange rate for its departure date, or none for
    its currency, can't be priced. It is left out of `cheapest-direct` and
    `cheapest`, and so is every route through it. The cheapest of the remaining
    routes is returned, even though an excluded route might have been cheaper,
    and stderr names each skipped sailing. `fastest` is not affected. EUR
    sailings never need an exchange rate.
11. A sailing with no entry in `rates` can't be quoted, so it is left out of
    every criterion, `fastest` included, and stderr names it.
12. Warnings name only sailings that sit on an otherwise valid route for the
    current search and criterion, each at most once. ETRB (ESBCN→BRSSZ), for
    example, is never reported for a CNSHA→NLRTM search.
13. Routes may have any number of legs. `cheapest-direct` considers single
    sailings only. `cheapest` and `fastest` consider direct and multi-leg routes,
    and `cheapest` compares the sum of the legs in EUR.
14. Money is calculated with BigDecimal, never floating point, and totals are
    not rounded before they are compared. Output repeats each rate exactly as
    the feed quotes it (`"97453"`, `"JPY"`), in the original currency.

## Input, output and running

15. Input is three lines: origin port, destination port, criterion. Surrounding
    whitespace is ignored, port codes are upper-cased and the criterion is
    matched case-insensitively. The answer comes right after the third line, so
    an interactive session doesn't need to close stdin. Input with fewer than
    three lines, a blank port, an unknown criterion, or the same origin and
    destination is rejected: there is a message on stderr, exit status 1,
    nothing on stdout, and nothing is saved.
16. stdout carries only the JSON result, which is `[]` when there is no route.
    Warnings, saved-search messages and errors go to stderr, so stdout always
    parses as JSON. A run that prints a result exits with status 0.
17. The feed is read from `response.json` (or from `FEED_PATH`) on every run,
    so a replaced file takes effect on the next run without a rebuild. If the
    file is missing or isn't valid JSON, the run stops with exit status 1,
    names the path on stderr, and leaves saved searches alone.
18. Docker with compose is the only thing installed. The app, Redis and the
    test suite all run through `docker compose`.

## Saved searches (SLD-0004)

19. There is a single user. A saved search is identified by origin,
    destination and criterion together. Saving it again keeps the one entry and
    its first save time. The same ports with another criterion are a separate
    search.
20. A search whose result is empty is saved, and stderr says it will be
    reported once an option becomes available.
21. Every run first re-evaluates all saved searches against the feed it just
    loaded, using the same rules as a normal search. Each saved search that now
    has a result is written to stderr (a header line followed by the route
    JSON), oldest first, and then removed. So it is reported once, also when
    two runs race: only the run that removes it reports it. This happens before
    the stdin search is answered, so a stdin search that matches a saved search
    fulfilled in the same run is answered and not saved again.
22. Saved searches are kept in Redis, run by docker compose, as one sorted set
    scored by save time. The Redis data directory is bind-mounted to
    `./data/redis` on the host, so it survives `docker compose down` (with or
    without `-v`) and removal of containers and images. Redis uses its default
    snapshots and no append-only file, so a Redis crash can lose the most recent
    saves. That's acceptable: the user can repeat the search.
23. If Redis can't be reached, the search is still answered and the run exits
    with status 0. stderr warns that saved searches could not be checked or
    the search could not be saved.

## Persistence trade-offs considered

| Option | For | Against |
| --- | --- | --- |
| JSON file on a bind mount | No extra service | Concurrent runs need file locking; read-modify-write races can lose saves or notify twice |
| SQLite on a bind mount | Transactions in a single file | Native gem and a schema for what is a three-operation store |
| Redis with a named volume | Managed by Docker | `docker compose down -v` and `docker volume prune` delete it |
| **Redis, bind mount, default snapshots (chosen)** | `ZADD NX` deduplicates and `ZREM` succeeds once, so each search is reported exactly once; data stays as plain files on the host and survives `down -v` | An extra container; the last few saves can be lost if Redis crashes |
| Redis with AOF | No lost saves | More disk writes, for data the user can simply re-enter |

How the user is told: on stderr, in the next run of any search. Alternatives
were a separate "check my saved searches" command, which the user has to
remember to run, and email or webhooks, which need infrastructure and a user
identity we don't have.

## Questions for the PO

- **TST-0003:** Should waiting time in port count toward "fastest"? We assumed
  yes (#8), which gives QRST rather than ERXQ+ETRG from the example. If only time
  at sea counts, the answer changes.
- **TST-0003:** Should a tie on journey time be broken by price instead of feed
  order (#9)?
- **PLS-0001 / WRT-0002:** When a sailing can't be priced for lack of an
  exchange rate, is it acceptable to return a possibly more expensive route
  with a warning (#10)? Alternatives are to use the nearest earlier exchange
  rate or to refuse to answer.
- **PLS-0001 / WRT-0002:** Should a tie on price be broken by journey time or
  departure date instead of feed order (#9)?
- **PLS-0001 / WRT-0002 / TST-0003:** Is "last rate wins" right for duplicate
  rates (#3), or does the feed have a timestamp or provider priority we should
  use? Can the same `sailing_code` appear twice in `sailings`? We currently
  treat such entries as separate sailings.
- **WRT-0002 / TST-0003:** Is there a maximum number of legs, a minimum
  transfer time in port (we allow same-day transfers, #4), or a maximum wait?
- **SLD-0004:** How should users be told in production: stderr on the next run
  (as now), email, or a webhook? Will there be more than one user, so that saved
  searches need an owner?
- **SLD-0004:** Should saved searches expire? Port-code typos are currently
  saved indefinitely.
- **SLD-0004:** Once a saved search is fulfilled, should we also report later,
  better options, or is one notification enough?
- **All tickets:** Should unknown port codes be rejected against a port list,
  rather than searched (and saved) as given?
