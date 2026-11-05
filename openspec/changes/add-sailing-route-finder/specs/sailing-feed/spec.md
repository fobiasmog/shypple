## Purpose

Loads the MapReduce JSON feed (sailings, rates, EUR-based exchange rates) and turns it into clean, trustworthy data. It resolves conflicting or missing entries and converts sailing rates to EUR, so route search can compare options fairly.

## ADDED Requirements

### Requirement: Feed is loaded from a configurable JSON file
The system SHALL read the feed from the JSON file at the path in the `FEED_PATH` environment variable. If the variable is not set, it SHALL use the bundled default path. The feed SHALL be read again on every run, so a replaced file takes effect on the next run without a rebuild.

#### Scenario: Default feed path
- **WHEN** the CLI runs without `FEED_PATH` set
- **THEN** the system loads sailings, rates and exchange rates from the default `response.json`

#### Scenario: Replaced feed is picked up on next run
- **WHEN** the feed file is replaced with a version that has extra sailings and the CLI runs again
- **THEN** the extra sailings are available to every search in that run

#### Scenario: Feed file missing or not valid JSON
- **WHEN** `FEED_PATH` points to a file that does not exist or does not contain valid JSON
- **THEN** loading fails with an error message that names the path and the reason

### Requirement: Duplicate rates resolve to the last entry
When the `rates` array has more than one entry for the same `sailing_code`, the system SHALL use the entry that appears last in the array. The array is assumed to run from oldest to newest.

#### Scenario: Conflicting MNOP rates
- **WHEN** the feed has MNOP at `456.78 USD` followed by MNOP at `812.00 USD`
- **THEN** MNOP is quoted at `812.00 USD`

### Requirement: Sailings without a rate are unquotable
A sailing whose `sailing_code` has no entry in `rates` SHALL be marked unquotable. An unquotable sailing has no price and no currency.

#### Scenario: Sailing with no rate entry
- **WHEN** the feed has a sailing `ZZZZ` and no rate entry for `ZZZZ`
- **THEN** `ZZZZ` is marked unquotable

### Requirement: Rates convert to EUR using the departure-date exchange rate
For a non-EUR rate, the system SHALL compute the EUR amount as the rate amount divided by the exchange rate for that currency, taken from the `exchange_rates` entry for the sailing's `departure_date`. Currency codes SHALL match regardless of case (for example `USD` in a rate matches `usd` in the exchange rates).

#### Scenario: USD sailing converted on its departure date
- **WHEN** ABCD is quoted at `589.30 USD`, departs `2022-02-01`, and the USD exchange rate for `2022-02-01` is `1.126`
- **THEN** the EUR cost of ABCD is `589.30 / 1.126` ≈ `523.357016`

#### Scenario: JPY sailing converted on its departure date
- **WHEN** IJKL is quoted at `97453 JPY`, departs `2022-01-31`, and the JPY exchange rate for `2022-01-31` is `131.2`
- **THEN** the EUR cost of IJKL is `97453 / 131.2` ≈ `742.78`

### Requirement: EUR rates need no exchange rate
A rate already in EUR SHALL be used as its EUR cost directly. It SHALL NOT require any exchange-rate entry, even when the departure date is missing from `exchange_rates`.

#### Scenario: EUR sailing on a date without exchange rates
- **WHEN** a sailing is quoted at `261.96 EUR` and its departure date has no entry in `exchange_rates`
- **THEN** its EUR cost is `261.96`

### Requirement: Missing exchange rate makes a sailing unpriceable in EUR
If a non-EUR sailing's departure date has no `exchange_rates` entry, or the entry has no rate for the sailing's currency, the sailing SHALL be marked unpriceable in EUR. The sailing SHALL stay quotable, with its original rate and currency.

#### Scenario: Departure date missing from exchange rates
- **WHEN** ETRG is quoted at `69.96 USD`, departs `2022-02-16`, and `exchange_rates` has no `2022-02-16` entry
- **THEN** ETRG is unpriceable in EUR but still quotable at `69.96 USD`

#### Scenario: Currency missing for the departure date
- **WHEN** a sailing is quoted in `GBP` and the exchange-rate entry for its departure date only has `usd` and `jpy`
- **THEN** the sailing is unpriceable in EUR

### Requirement: Monetary values use exact decimal arithmetic
Rate amounts, exchange rates, EUR conversions and route totals SHALL be calculated with exact decimal arithmetic, never binary floating point. Values SHALL NOT be rounded before they are compared.

#### Scenario: Close totals compare correctly
- **WHEN** ERXQ+ETRG totals ≈ `322.890152 EUR` and ERXQ+ETRF totals ≈ `323.755698 EUR`
- **THEN** ERXQ+ETRG compares as cheaper, using the unrounded totals
