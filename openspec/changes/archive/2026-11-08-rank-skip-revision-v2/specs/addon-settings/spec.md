# Spec Delta

## ADDED Requirements

### Requirement: Skip revision choice
The system SHALL provide a choice of skip revision on the Tuning section, listing each revision with a one-line description and marking the newest as the default. Choosing one SHALL take effect at once for later purchases, and the choice SHALL be saved. Players who never choose SHALL be on the newest revision.

#### Scenario: Default shown
- **WHEN** a player who never chose opens Tuning
- **THEN** revision 2 is selected and marked as the default

#### Scenario: Go back
- **WHEN** the player selects revision 1
- **THEN** the Rules page and the trainer window use revision 1 from then on

#### Scenario: Description
- **WHEN** the player reads the choice
- **THEN** revision 1 is described as "Original using Expert Advice" and revision 2 as "Revised with Rules + Expert Advice"

### Requirement: Rules page shows the revision, source and reason
The system SHALL show on the Rules page the revision in use and, for every rank in Ranks to skip, the reason it is skipped. For skips whose decision was computed, the page SHALL also say that it was computed, and for skips that came from a Wowhead guide it SHALL say so. The list SHALL follow the chosen revision.

#### Scenario: Revision named
- **WHEN** the player opens the Rules page
- **THEN** the page names the revision in use

#### Scenario: Computed skip
- **WHEN** a rank is skipped by a computed decision
- **THEN** the Rules page lists its reason and says the decision was computed from the game data

#### Scenario: Guide skip
- **WHEN** a rank is skipped on a Wowhead guide's advice
- **THEN** the Rules page lists its reason and says it comes from the Wowhead guide

#### Scenario: Revision switched
- **WHEN** the player switches to revision 1
- **THEN** Ranks to skip lists revision 1's ranks with the reason revision 1 records for each
