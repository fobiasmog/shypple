## Using AI

**Use AI — we expect it. We're evaluating how you direct it, not whether you can
avoid it.**

In the next phase we will ask you to walk us through your solution and explain
the decisions behind it. You should be able to explain what you did and why —
candidates who can't explain their own submission will not advance.

The interview also has a separate **PR review** part. That one is not your
submission: we give you a pull request on a different codebase, related to this
exercise, and ask you to review it with us — what you would comment on, what you
would block, and what you would let go.

Both parts happen live, so expect to read and reason about code out loud.

## Background

Shypple is a freight forwarder company. That means we help other companies to
get their products from one place to another. We must deliver the goods as fast
as possible. To achieve that, we need to replace some human labor with
automation. We have part of the process being done via Excel and that is not
good to scale.

Have we told you we want to be the biggest freight forwarder company in the
world?

The good news is the team MapReduce (yeah, they choose this name) already
created a service that aggregates lots of information and returns a JSON file
for us. This MapReduce service returns all shipping options available in the
database. We have given you a sample JSON response from MapReduce service.

Your job is to create a small service that does some calculations using the
JSON file.

Exchange rates in the JSON file are based on EUR (For example 2022-01-29 usd
rate 1.1138 is USD/EUR rate). We decide which exchange_rate will be used to
calculate EUR sailing rate based on the *departure_date* of the sailing. Use
sailing_code from sailing & rate to get the rate amount & currency.

Your Product Owner created 4 tickets for you: PLS-0001, WRT-0002, TST-0003 and
SLD-0004. All four are required.

The solution should include all configuration files needed to build and run in
a Docker container (don't expect anything else but Docker to be installed).

### Input/Output Specification
1. The first line is the origin_port code
2. The second line is the destination_port code
3. The third line is the criteria (cheapest-direct, cheapest, fastest)
4. The next lines you should print the result

#### Input
```json
CNSHA
NLRTM
cheapest-direct
```

#### Output
```json
[
  {
    "origin_port": "CNSHA",
    "destination_port": "NLRTM",
    "departure_date": "2024-02-01",
    "arrival_date": "2024-03-01",
    "sailing_code": "XXXX",
    "rate": "123.00",
    "rate_currency": "USD"
  }
]
```

#### (1) PLS-0001 - *Acceptance criteria*: Return the cheapest direct sailing between origin port & destination port in following format. For example using CNSHA as origin port & NLRTM as destination port input parameters


```json
CNSHA
NLRTM
cheapest-direct
[
  {
    "origin_port": "CNSHA",
    "destination_port": "NLRTM",
    "departure_date": "2024-02-01",
    "arrival_date": "2024-03-01",
    "sailing_code": "XXXX",
    "rate": "232.30",
    "rate_currency": "USD"
  }
]
```

#### (2) WRT-0002 - *Acceptance criteria*: Return the cheapest sailing (direct or indirect). If the cheapest one contains more than one sailing (two sailings) in the following format, you should return all sailing legs (You need to compare the sum of all sailing legs to find the cheapest sailing option). Use same CNSHA as origin port & NLRTM as destination port input parameters

#### Input
```json
CNSHA
NLRTM
cheapest
```

#### Output
```json
[
  {
    "origin_port": "CNSHA",
    "destination_port": "ESBCN",
    "departure_date": "2022-01-29",
    "arrival_date": "2022-02-06",
    "sailing_code": "ERXQ",
    "rate": "261.96",
    "rate_currency": "EUR"
  },
  {
    "origin_port": "ESBCN",
    "destination_port": "NLRTM",
    "departure_date": "2022-02-16",
    "arrival_date": "2022-02-20",
    "sailing_code": "ETRG",
    "rate": "69.96",
    "rate_currency": "USD"
  }
]
```

#### (3) TST-0003 - *Acceptance criteria*: Return the fastest sailing legs (direct or indirect) in the same above format
##### Definition of "fastest": the sailing leg(s) with the shortest total journey time between the origin and destination.

#### Input
```json
CNSHA
NLRTM
fastest
```

#### Output
```json
[
  {
    "origin_port": "CNSHA",
    "destination_port": "ESBCN",
    "departure_date": "2022-01-29",
    "arrival_date": "2022-02-06",
    "sailing_code": "ERXQ",
    "rate": "261.96",
    "rate_currency": "EUR"
  },
  {
    "origin_port": "ESBCN",
    "destination_port": "NLRTM",
    "departure_date": "2022-02-16",
    "arrival_date": "2022-02-20",
    "sailing_code": "ETRG",
    "rate": "69.96",
    "rate_currency": "USD"
  }
]
```

#### (4) SLD-0004 - *Acceptance criteria*: Save a search now, fulfill it later.

A user may search for a route we have no option for yet (no direct or indirect
path between origin and destination for the given criteria). Instead of simply
returning an empty result, the system should **save** that search request.

Later, a new MapReduce feed arrives with more sailings. Any previously saved
search that can **now** be fulfilled should be surfaced back to the user.

It is up to you to decide *how* to persist saved searches and *how* to inform
the user once a match becomes available (remember: Docker is the only thing we
can assume is installed). Choose the approach you think best fits the problem
and **document your assumptions and the trade-offs you considered.**

#### (5) DRY-0005 - coming soon

#### (6) TDD-0006 - coming soon

### Project Requirements

1. The solution must be written in Ruby.
2. Please, create one single branch for all the changes.
3. Make sure your app run on docker and all the dependencies are included on it
4. Please send a zip file with the solution to this email address, j.souza@shypple.com and n.vannederpelt@shypple.com, once you're done.
5. The solution must work with standard input and output (stdin and stdout).
6. For indirect routes, the solution should handle more than two legs.

You should provide a solution that make possible to scale because new requirements will come soon.

We will evaluate the solution with some criteria:

1. Object Oriented Concepts
2. SOLID
3. DRY
4. Test Coverage

#### Lingo

CNSHA - Shanghai

NLRTM - Rotterdam

ESBCN - Barcelona

BRSSZ - Santos

Shipment Leg: A "shipment leg" refers to each segment of a shipment's journey
between two specific locations, such as from one port to another. For example,
if a shipment travels from Shanghai to Rotterdam with a stopover in Barcelona,
the journey consists of two legs: Shanghai to Barcelona and Barcelona to
Rotterdam.

#### Assumptions & Data Quality

The MapReduce feed is aggregated from multiple upstream providers, so the data is
not guaranteed to be clean. For example, the same sailing may appear more than
once with conflicting rates from different feeds — it is up to you to decide which
one wins and to justify it.

The data and spec are deliberately incomplete in places, as real tickets are.
Document any assumptions you made and any questions you'd ask the PO.

#### We are here to help

Feel free to reach out to us with any questions or concerns you may have. We're
here to help and are more than happy to provide any clarification needed.

Good luck!

:q!
