# Route search: DFS vs Dijkstra — notes

_2026-11-09_

## Summary

Keep the depth-first search for the submission. If feeds grow, switch to
**Pareto-label Dijkstra over ports**, behind the same `RouteFinder#find`.

- The depth-first search is 35 lines and follows every agreed rule exactly. It
  lists every valid route, so the work grows exponentially with feed size.
- Pareto-label Dijkstra keeps several (cost, arrival) labels per port. Its work
  grows polynomially, and it drops loops without extra code.
- It costs about 100–130 more lines, a heap, a wider criterion interface and a
  change to tie rule #9.

## Current algorithm: exhaustive depth-first search

`RouteFinder#find` (`lib/route_finder/route_finder.rb`) lists every valid route,
drops the ones the criterion can't use, and keeps the lowest score.

```
sailings ──► 1. INDEX ──► 2. ENUMERATE ──► 3. FILTER ──► 4. SELECT ──► Result(route, skipped)
            group by     depth-first      criterion     strict "<"
            origin port  over valid paths .eligible?    on .score
```

1. **Index** (`:15`): `sailings.group_by(&:origin)` gives the departures per
   port, in feed order.
2. **Enumerate** (`:32–45`): a recursive walk from the origin. It skips a
   sailing whose destination is already visited (`:36`), or one that departs
   before the previous leg arrives (`:47`). When a sailing reaches the
   destination, the path is yielded and the walk goes no deeper.
3. **Filter** (`:20–23`): a path with an ineligible leg is dropped, and that
   leg is recorded once, with its reason, in `skipped`.
4. **Select** (`:50–52`): every route is scored, and a candidate replaces the
   current best only when it is strictly lower.

Walk for CNSHA → NLRTM on the sample feed:

```
CNSHA   ports=[CNSHA]  legs=[]
├── ABCD → NLRTM  ✔ yield [ABCD]
├── EFGH → NLRTM  ✔ yield [EFGH]
├── IJKL → NLRTM  ✔ yield [IJKL]
├── MNOP → NLRTM  ✔ yield [MNOP]
├── QRST → NLRTM  ✔ yield [QRST]
└── ERXQ → ESBCN (arrives 02-12)    ports=[CNSHA, ESBCN]
    ├── ETRF departs 02-15 ≥ 02-12 → NLRTM  ✔ yield [ERXQ, ETRF]
    ├── ETRG departs 02-16 ≥ 02-12 → NLRTM  ✔ yield [ERXQ, ETRG]
    └── ETRB → BRSSZ                ports=[CNSHA, ESBCN, BRSSZ]
        └── (nothing leaves BRSSZ) ✘ dead end
```

| Candidate (walk order) | cheapest (EUR) | fastest (days) |
|---|---|---|
| ABCD | 523.36 | 28 |
| EFGH | 890.32 | 28 |
| IJKL | 742.78 | 28 |
| MNOP | 729.04 | 34 |
| QRST | 761.96 | **17 ← winner** |
| ERXQ+ETRF | 323.76 | 59 |
| ERXQ+ETRG | **322.89 ← winner** | 22 |

What comes for free:

- **Ties (#9):** the walk yields routes ordered by the feed positions of their
  legs, so the strict `<` keeps the first of several equal routes.
- **Relevant-only warnings (#12):** only complete paths are filtered, so ETRB
  (whose path dead-ends) is never reported for CNSHA → NLRTM.
- **No port twice (#5, #6):** a single `ports.include?` check.
- **`max_legs`:** a single check at the top of each call. For cheapest-direct it
  stops the walk at depth 1.

What it costs: one unit of work per valid route. A chain of k hops with m
sailings per hop has mᵏ routes. With m = 10 that is 10⁶ routes at 6 hops and
10⁸ at 8 hops. Each run searches once per saved search plus once for stdin.

## Why plain Dijkstra over ports fails

Textbook Dijkstra keeps one best label per port. With time windows, that loses
routes that need an earlier but dearer arrival. A hypothetical example:

```
  C1  €100, arrives ESBCN 02-17 ─┐
                                 ├─► ESBCN ── ETRG €60, departs 02-16 ──► NLRTM
  D1  €200, arrives ESBCN 02-12 ─┘
```

Classic Dijkstra settles ESBCN at €100, then can't catch ETRG. The valid route
D1+ETRG (€260) is lost. There are two ways out: make sailings the nodes
(Option A), or keep several labels per port (Option B).

## Option A: sailings as nodes

Each sailing is a node. There is an edge `p → s` when `p` arrives at `s`'s origin
on or before `s` departs. A node carries its own arrival date, so one label per
node is correct.

Each criterion must become a cost per step that is never negative:

| Criterion | `step_cost(previous, sailing)` |
|---|---|
| cheapest | `to_eur(sailing)` |
| fastest | `sailing.arrival − (previous ? previous.arrival : sailing.departure)` |

The fastest steps add up to the journey time:
`(a₁ − d₁) + Σᵢ₌₂ⁿ (aᵢ − aᵢ₋₁) = aₙ − d₁`.

**Problem: loops tie for fastest.** Nodes don't track visited ports. For
cheapest a loop always costs more, but for fastest a loop ties with its shortcut.
The fixture in `route_finder_spec.rb` shows it:

```
AX 01-01→01-02 (pos 0), XB 01-03→01-04 (pos 1), BX 01-05→01-06 (pos 2), XC 01-07→01-08 (pos 3)
  A→X→C        = 7 days, positions [0,3]
  A→X→B→X→C    = 7 days, positions [0,1,2,3]   ← compares smaller, so the loop wins
```

Fix: break ties on fewer legs first (this changes #9), or strip loops from the
result afterwards.

## Option B: Pareto-label Dijkstra over ports

Each port keeps every label that no other label beats on both cost and time. A
sailing is taken only if it departs on or after the label's arrival. In the
C1/D1 case, ESBCN keeps both (€100, 02-17) and (€200, 02-12). ETRG is possible
only from the second, which gives €260.

| Criterion | Label | Queue key (never decreases) | A beats B when |
|---|---|---|---|
| cheapest | (EUR so far, arrival) | EUR so far | A.cost ≤ B.cost and A.arrival ≤ B.arrival |
| fastest | (first departure, arrival) | arrival − first departure | A left no earlier and arrived no later |

Sample traces:

```
cheapest
pop CNSHA (0)          → NLRTM: ABCD (523.36, 03-01), IJKL (742.78, 02-28), QRST (761.96, 02-15), …
                       → ESBCN: ERXQ (261.96, 02-12)
pop ESBCN (261.96)     → NLRTM: ETRG (322.89, 02-20), ETRF (323.76, 03-29); BRSSZ: ETRB (645.13, 03-14)
pop NLRTM (322.89)     → destination → ERXQ+ETRG

fastest
pop CNSHA              → ESBCN via ERXQ (14), NLRTM via QRST (17), ABCD/EFGH/IJKL (28), MNOP (34)
pop ESBCN (14)         → NLRTM via ETRG (22), ETRF (59); BRSSZ via ETRB (44)
pop NLRTM (17)         → destination → QRST
```

Both stop after 3 pops, where the depth-first search lists 7 complete routes.

**What it fixes compared with Option A:**

- Loops disappear without extra code. Coming back to a port means arriving later
  at the same or higher cost, so the earlier label beats it.
- One search engine serves both criteria. Only the label and the "beats" rule
  differ.

**What it still needs:**

- **A priority queue.** Ruby's standard library has none, so about 30 lines of
  heap, or a gem.
- **A warnings pass.** Reporting relevant skipped sailings needs a separate
  forward and backward reachability pass, about 15–20 lines. In rare cases it
  can over-report, because the reachability passes ignore the no-repeat rule.
- **`max_legs`.** Either leg count becomes a label field, or direct-only is a
  special case (one line for cheapest-direct).
- **A wider criterion interface.** Each criterion supplies start, extend, queue
  key and "beats", in place of `score(route)`.

**Tie rule change.** Labels naturally prefer the earlier arrival when costs are
equal. With (cost, arrival) as the key, the `ties` fixture's cheapest search
returns EEEE (€300, arrives 02-11), not today's AAAA+BBBB. There are two choices:

- keep feed order by putting leg positions into the keys (more labels survive,
  and the keys get clumsy);
- change #9 to "same cost → earlier arrival → feed order" (needs the PO, then
  updates to `assumptions.md` and three specs).

## Costs (estimates)

| | DFS (now) | Option A: sailings as nodes | Option B: Pareto labels |
|---|---|---|---|
| `route_finder.rb` code lines | 35 | ~90–110 | ~70–90 |
| Heap | none | ~30 lines or a gem | ~30 lines or a gem |
| `criteria.rb` | 31 (`score(route)`) | ~35 (`step_cost`) | ~45 (start, extend, key, beats) |
| App total | ~450 lines, 12 files | ~520–560, 13 files | ~540–580, 13 files |
| Worst-case work | exponential in routes | ~E log N over sailings | ~N² log N in sailings |
| No port twice | built in | extra code for fastest ties | built in (dominance) |
| Tie rule #9 | built in | positions in key | change the rule, or positions in key |
| Relevant-only warnings | built in | extra pass, ~20 lines | extra pass, ~15–20 lines |
| What a criterion can be | any route-level score | an additive, never-negative step cost | label + key + "beats" |

Specs: the tests that record candidate order go away, because nothing is
enumerated any more. Specs for the engine, the heap and the warnings pass come in.
The tie specs are rewritten if #9 changes.

## Cheaper steps before a full switch

1. **Branch-and-bound on the depth-first search** (+5–8 lines). Stop extending a
   partial route once its score is ≥ the best found so far.
   - It is safe because scores only grow as legs are added, and ties already go
     to the earlier route.
   - `score(route)` already works on partial routes, so the interface doesn't
     change.
   - Catch: a pruned branch can hide a skipped sailing, so the warnings need care.
   - Worst case stays exponential.
2. **One pass in departure order** (Option A without a heap, about 35 fewer
   lines).
   - Connections always depart later than the previous leg, so the sailing graph
     has no cycles. Processing sailings sorted by departure date gives the same
     answer as Dijkstra.
   - It needs the same interface change and the same loop and warning handling
     as Option A.

## Recommendation and interview talking points

- **Submission:** keep the depth-first search.
- **Scaling path:** measure first, then branch-and-bound, then Pareto-label
  Dijkstra. All of them fit behind `RouteFinder#find`, so the CLI and its
  specs don't change.

Talking points:

- **Why depth-first search:** 35 lines, exact on every agreed rule, instant at
  sample size.
- **When it breaks:** the number of routes grows as mᵏ, and each run repeats the
  search for every saved search.
- **The Dijkstra trap:** one label per port is wrong when sailings have dates;
  the C1/D1 example shows why.
- **The right variant:** Pareto labels of (cost, arrival). Loops disappear by
  dominance.
- **The price:** ~100–130 lines, a heap, a wider criterion interface and a change
  to the tie rule.

Open question for the PO, needed before Option B:

- [ ] **PLS-0001 / WRT-0002 / TST-0003:** when two routes tie, may the earlier
  arrival win before feed order?
