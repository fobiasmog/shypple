# route-search Specification

## Purpose

Finds valid direct and multi-leg sailing routes between two ports and picks the best one for a requested criterion (`cheapest-direct`, `cheapest`, `fastest`). Results are deterministic, and the handling of sailings that can't be quoted or priced is spelled out.

## Requirements

### Requirement: Legs of a route connect in place and time
A route SHALL be an ordered sequence of one or more sailings. It SHALL start at the requested origin port and end at the requested destination port. For every pair of consecutive legs:
- the destination port of one leg SHALL equal the origin port of the next;
- the earlier leg's `arrival_date` SHALL be on or before the later leg's `departure_date`.

A same-day transfer is allowed.

#### Scenario: Valid transfer with waiting time
- **WHEN** ERXQ (CNSHA→ESBCN) arrives `2022-02-12` and ETRF (ESBCN→NLRTM) departs `2022-02-15`
- **THEN** ERXQ followed by ETRF is a valid CNSHA→NLRTM route

#### Scenario: Same-day transfer
- **WHEN** one leg arrives at a port on `2022-02-16` and a sailing from that port departs on `2022-02-16`
- **THEN** the two legs form a valid connection

#### Scenario: Next leg departs before the previous one arrives
- **WHEN** one leg arrives at ESBCN on `2022-02-12` and a sailing from ESBCN departs on `2022-02-10`
- **THEN** the two legs do not form a valid connection

### Requirement: A route never visits a port twice
A route SHALL NOT pass through any port more than once, the origin and destination included.

#### Scenario: Round trip excluded
- **WHEN** the feed has sailings A→B and B→A on any dates
- **THEN** no route contains A→B→A

#### Scenario: Revisiting an intermediate port excluded
- **WHEN** the feed has sailings A→X, X→B, B→X and X→C
- **THEN** A→X→B→X→C is not a valid A→C route

### Requirement: Routes may have any number of legs
Route search SHALL NOT limit the number of legs, except where a criterion asks for direct sailings only.

#### Scenario: Three-leg route
- **WHEN** the only connection from A to D is A→B, B→C, C→D with valid transfer dates
- **THEN** `cheapest` and `fastest` for A→D both return the three legs in travel order

### Requirement: cheapest-direct returns the cheapest single sailing
For `cheapest-direct`, the system SHALL consider only single-leg routes from origin to destination. It SHALL return the one with the lowest EUR cost.

#### Scenario: Sample feed CNSHA to NLRTM
- **WHEN** the criterion is `cheapest-direct` from CNSHA to NLRTM on the sample feed
- **THEN** the result is ABCD alone (`589.30 USD`, ≈ `523.36 EUR`)

#### Scenario: Only indirect routes exist
- **WHEN** the criterion is `cheapest-direct` from CNSHA to BRSSZ on the sample feed (reachable only through ESBCN)
- **THEN** the result is empty

### Requirement: cheapest returns the route with the lowest total EUR cost
For `cheapest`, the system SHALL consider direct and multi-leg routes. It SHALL return the route whose legs have the lowest total EUR cost.

#### Scenario: Sample feed CNSHA to NLRTM
- **WHEN** the criterion is `cheapest` from CNSHA to NLRTM on the sample feed
- **THEN** the result is ERXQ followed by ETRG (≈ `322.89 EUR` in total), cheaper than every direct sailing and than ERXQ+ETRF

### Requirement: fastest returns the route with the shortest total journey time
For `fastest`, the system SHALL consider direct and multi-leg routes. It SHALL return the route with the fewest days between the first leg's `departure_date` and the last leg's `arrival_date`. Waiting time in transfer ports counts toward the journey time.

#### Scenario: Sample feed CNSHA to NLRTM
- **WHEN** the criterion is `fastest` from CNSHA to NLRTM on the sample feed
- **THEN** the result is QRST alone (`2022-01-29` → `2022-02-15`, 17 days), not ERXQ+ETRG (`2022-01-29` → `2022-02-20`, 22 days)

#### Scenario: Waiting time counts
- **WHEN** a two-leg route spends 10 days at sea in total and 15 days waiting in port
- **THEN** its journey time is 25 days

### Requirement: Ties go to the first route found in feed order
When two or more candidate routes have the same value for the requested criterion (the same EUR cost for cost criteria, the same journey time for `fastest`), the system SHALL return the first of them. Routes SHALL be ordered by the feed positions of their legs: compare the first legs' positions in the `sailings` array, then the second legs', and so on.

#### Scenario: Two direct sailings with equal EUR cost
- **WHEN** sailings P and Q go from the same origin to the same destination with equal EUR cost, and P comes before Q in `sailings`
- **THEN** `cheapest-direct` and `cheapest` return P

#### Scenario: Two routes with equal journey time
- **WHEN** two routes have the same journey time, and the first leg of one comes earlier in `sailings`
- **THEN** `fastest` returns the route whose first leg comes earlier

### Requirement: Unquotable sailings are excluded from every criterion
A route containing an unquotable sailing (one with no rate) SHALL NOT be returned for any criterion. The system SHALL write a warning to stderr naming that sailing.

#### Scenario: Fastest route has a leg without a rate
- **WHEN** the shortest route by journey time contains a sailing with no rate entry
- **THEN** `fastest` returns the fastest route made only of quotable sailings, and stderr names the excluded sailing

### Requirement: Unpriceable sailings are excluded from cost criteria only
A route containing a sailing that is unpriceable in EUR SHALL NOT be returned for `cheapest-direct` or `cheapest`. The system SHALL return the cheapest of the remaining routes, even though an excluded route might have been cheaper, and SHALL write a warning to stderr naming each excluded sailing. Such routes SHALL remain eligible for `fastest`.

#### Scenario: Cheapest route has a leg without an exchange rate
- **WHEN** the feed has no exchange rate for `2022-02-16` (so USD sailing ETRG can't be converted) and the criterion is `cheapest` from CNSHA to NLRTM
- **THEN** the result is ERXQ followed by ETRF (≈ `323.76 EUR`), and stderr names ETRG as skipped for missing exchange rate

#### Scenario: Fastest ignores missing exchange rates
- **WHEN** the fastest route contains a non-EUR sailing with no exchange rate for its departure date
- **THEN** `fastest` still returns that route, and no exchange-rate warning is written

#### Scenario: EUR legs never trigger exchange-rate exclusion
- **WHEN** a route is made only of EUR-quoted sailings whose departure dates have no exchange-rate entries
- **THEN** the route is eligible for cost criteria

### Requirement: Warnings cover only sailings relevant to the search
Exclusion warnings SHALL be written only for sailings that belong to at least one otherwise valid candidate route for the current search and criterion. Each sailing SHALL be named at most once per search.

#### Scenario: Irrelevant bad sailing is not reported
- **WHEN** ETRB (ESBCN→BRSSZ) can't be priced and the search is `cheapest` from CNSHA to NLRTM
- **THEN** no warning mentions ETRB

#### Scenario: Sailing appearing in several excluded routes
- **WHEN** an unpriceable sailing appears in three candidate routes for a `cheapest` search
- **THEN** stderr names that sailing exactly once

### Requirement: No eligible route yields an empty result
When no eligible route exists for the requested origin, destination and criterion, the search result SHALL be empty.

#### Scenario: No sailings leave the origin
- **WHEN** the search is `cheapest` from NLRTM to CNSHA on the sample feed
- **THEN** the result is empty
