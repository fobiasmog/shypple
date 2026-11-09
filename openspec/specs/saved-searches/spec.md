# saved-searches Specification

## Purpose

Remembers searches that can't be fulfilled from the current feed and tells the user, once, when a later feed can fulfil them (SLD-0004). An empty answer becomes a deferred one.

## Requirements

### Requirement: Unfulfilled searches are saved
When a search from stdin returns an empty result, the system SHALL save that search (origin port, destination port, criterion) to persistent storage. It SHALL write a message to stderr saying the search was saved and the user will be notified when an option becomes available.

#### Scenario: No route from NLRTM to CNSHA
- **WHEN** the user searches `NLRTM`, `CNSHA`, `cheapest` on the sample feed
- **THEN** stdout shows an empty result, the search is saved, and stderr confirms it was saved

#### Scenario: Fulfilled search is not saved
- **WHEN** the user searches `CNSHA`, `NLRTM`, `cheapest` on the sample feed
- **THEN** nothing is saved

### Requirement: Saved searches are unique by origin, destination and criterion
A saved search SHALL be identified by origin port, destination port and criterion together. Saving a search that is already saved SHALL NOT create a second entry and SHALL keep the original save time.

#### Scenario: Same search repeated
- **WHEN** the user runs the unfulfillable search `NLRTM`, `CNSHA`, `cheapest` twice
- **THEN** exactly one saved search exists for it, with the time of the first save

#### Scenario: Same ports, different criterion
- **WHEN** `CNSHA`, `BRSSZ`, `cheapest-direct` is saved, and `CNSHA`, `BRSSZ`, `cheapest` is searched
- **THEN** the two are treated as separate searches

### Requirement: Saved searches are re-evaluated on every run
On every run, before answering the search from stdin, the system SHALL evaluate every saved search against the feed loaded in that run. It SHALL use the same route-search rules as a normal search.

#### Scenario: New feed adds a missing route
- **WHEN** `NLRTM`, `CNSHA`, `cheapest` is saved, the feed is replaced with one containing a sailing NLRTM→CNSHA, and the CLI runs with any valid input
- **THEN** the saved search is evaluated and found to be fulfilled in that run

### Requirement: Fulfilled saved searches are reported once and removed
For each saved search that is now fulfilled, the system SHALL write a notification to stderr and then remove the search from storage. The notification is a header line naming origin, destination and criterion, followed by the result in the same JSON format as stdout. A removed search SHALL NOT be reported again.

#### Scenario: Notification shape
- **WHEN** saved search `NLRTM`, `CNSHA`, `cheapest` becomes fulfilled
- **THEN** stderr shows a header such as `Saved search now available: NLRTM -> CNSHA (cheapest)`, followed by the JSON array of legs

#### Scenario: Not reported twice
- **WHEN** a saved search was reported in one run and the CLI runs again with the same feed
- **THEN** no notification is written for that search

#### Scenario: Still unfulfilled
- **WHEN** a saved search still has no result in the current feed
- **THEN** it stays saved and nothing is written about it

### Requirement: Notifications are written oldest first
When several saved searches become fulfilled in the same run, notifications SHALL be written in the order the searches were first saved, oldest first.

#### Scenario: Two searches fulfilled at once
- **WHEN** search S1 was saved before S2 and both become fulfilled in the same run
- **THEN** the notification for S1 is written before the one for S2

### Requirement: Each fulfilled search is reported exactly once across concurrent runs
If two runs evaluate the same fulfilled saved search at the same time, only one of them SHALL report it.

#### Scenario: Two simultaneous runs
- **WHEN** two CLI runs start at the same time and both find saved search S fulfilled
- **THEN** exactly one of the two runs writes the notification for S

### Requirement: Saved searches survive container and image removal
Saved searches SHALL persist on the host filesystem outside the containers. They SHALL survive stopping, removing or rebuilding the containers and images. Losing the most recently saved searches after an unclean crash of the storage service is acceptable.

#### Scenario: Containers removed and recreated
- **WHEN** a search is saved, then `docker compose down` is run, and the CLI is later started again
- **THEN** the saved search is still present and is re-evaluated

### Requirement: Search still works when storage is unavailable
If the saved-search storage can't be reached, the system SHALL still answer the search from stdin on stdout. It SHALL write a warning to stderr saying saved searches could not be checked or saved, and SHALL exit successfully.

#### Scenario: Storage down during a fulfillable search
- **WHEN** storage is unreachable and the user searches `CNSHA`, `NLRTM`, `cheapest`
- **THEN** stdout shows the ERXQ+ETRG result, stderr warns that saved searches could not be checked, and the exit status is success

#### Scenario: Storage down during an unfulfillable search
- **WHEN** storage is unreachable and the user searches `NLRTM`, `CNSHA`, `cheapest`
- **THEN** stdout shows an empty result and stderr warns that the search could not be saved
