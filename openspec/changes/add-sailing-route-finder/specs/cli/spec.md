## Purpose

Defines the command-line contract of the route finder: the stdin input format, the stdout result format, what goes to stderr, the order of steps in a run, exit codes, and running under Docker with nothing else installed.

## ADDED Requirements

### Requirement: Input is three lines on stdin
The CLI SHALL read exactly three lines from stdin, in this order: origin port code, destination port code, criterion. It SHALL NOT wait for end of input after the third line. Surrounding whitespace SHALL be ignored. Port codes SHALL be treated as case-insensitive and normalized to upper case. The criterion SHALL be one of `cheapest-direct`, `cheapest`, `fastest`, matched case-insensitively.

#### Scenario: Piped input
- **WHEN** stdin contains `CNSHA`, `NLRTM`, `cheapest-direct` on three lines
- **THEN** the CLI searches cheapest-direct from CNSHA to NLRTM

#### Scenario: Interactive input
- **WHEN** a user types three lines in an interactive session without closing stdin
- **THEN** the CLI answers right after the third line

#### Scenario: Lower-case and padded input
- **WHEN** stdin contains ` cnsha `, `nlrtm`, `Cheapest` on three lines
- **THEN** the CLI searches cheapest from CNSHA to NLRTM

### Requirement: Invalid input is rejected without side effects
If stdin has fewer than three lines, a blank port code, an unknown criterion, or the same origin and destination, the CLI SHALL write an error message to stderr and exit with a non-zero status. It SHALL write nothing to stdout and SHALL NOT save anything.

#### Scenario: Unknown criterion
- **WHEN** the third line is `cheapest-ever`
- **THEN** stderr lists the supported criteria, stdout is empty, and the exit status is non-zero

#### Scenario: Origin equals destination
- **WHEN** both port lines are `CNSHA`
- **THEN** stderr explains that origin and destination must differ and the exit status is non-zero

#### Scenario: Truncated input
- **WHEN** stdin closes after two lines
- **THEN** stderr reports missing input and the exit status is non-zero

### Requirement: Result is a JSON array of legs on stdout
The CLI SHALL write the search result to stdout as a JSON array, pretty-printed with two-space indentation, with one object per leg in travel order. Each object SHALL contain exactly these keys, in this order:
- `origin_port`
- `destination_port`
- `departure_date` (YYYY-MM-DD)
- `arrival_date` (YYYY-MM-DD)
- `sailing_code`
- `rate`: the rate string exactly as it appears in the feed, not converted
- `rate_currency`: the feed's currency code

An empty result SHALL be written as `[]`.

#### Scenario: Multi-leg result
- **WHEN** the search is `CNSHA`, `NLRTM`, `cheapest` on the sample feed
- **THEN** stdout is:
  ```json
  [
    {
      "origin_port": "CNSHA",
      "destination_port": "ESBCN",
      "departure_date": "2022-01-29",
      "arrival_date": "2022-02-12",
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

#### Scenario: Rate echoed in original currency
- **WHEN** the result contains IJKL quoted at `97453 JPY`
- **THEN** its object has `"rate": "97453"` and `"rate_currency": "JPY"`

#### Scenario: Empty result
- **WHEN** no route exists for the search
- **THEN** stdout is `[]`

### Requirement: stdout carries only the result
Warnings, saved-search confirmations, saved-search notifications and errors SHALL be written to stderr. Stdout SHALL contain only the JSON result, so it always parses as JSON.

#### Scenario: Warnings present
- **WHEN** a search produces exclusion warnings and saved-search notifications
- **THEN** stdout still parses as a single JSON array, and the messages appear only on stderr

### Requirement: A run follows a fixed sequence
Each run SHALL:
1. read and validate the input;
2. load the feed;
3. re-evaluate saved searches and report any that are fulfilled;
4. answer the search from stdin on stdout;
5. save the search if its result is empty.

#### Scenario: Stdin search matches a saved search that is now fulfilled
- **WHEN** saved search `NLRTM`, `CNSHA`, `cheapest` becomes fulfilled and the same search is given on stdin
- **THEN** stderr carries the notification, stdout carries the result, and the search is no longer saved

### Requirement: Feed errors stop the run
If the feed can't be loaded, the CLI SHALL write an error naming the feed path to stderr and exit with a non-zero status. It SHALL NOT change saved searches.

#### Scenario: Feed file missing
- **WHEN** `FEED_PATH` points to a missing file
- **THEN** stderr names the path, stdout is empty, the exit status is non-zero, and saved searches are unchanged

### Requirement: Successful runs exit with status zero
A run that writes a result to stdout SHALL exit with status 0. This includes empty results and runs where saved-search storage was unavailable.

#### Scenario: Empty result exit status
- **WHEN** a valid search returns `[]`
- **THEN** the exit status is 0

### Requirement: Runs with only Docker installed
The project SHALL ship a `Dockerfile` and a `docker-compose.yml`. With only Docker installed, a user SHALL be able to build the app and run searches with docker compose, including the storage service, both piped and interactive. The test suite SHALL also run through docker compose.

#### Scenario: Piped run through docker compose
- **WHEN** a user with only Docker installed runs `docker compose run --rm -T app < input.txt`, where `input.txt` holds a valid three-line search
- **THEN** the result JSON is printed to stdout

#### Scenario: Test suite through docker compose
- **WHEN** a user runs the documented docker compose test command
- **THEN** the full test suite runs and reports results and coverage
