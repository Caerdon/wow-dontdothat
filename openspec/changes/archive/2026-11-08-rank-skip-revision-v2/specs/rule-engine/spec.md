# Spec Delta

## MODIFIED Requirements

### Requirement: Explicit rank skips
The system SHALL let the chosen skip revision name individual spell ranks to skip, SHALL defer a named rank even when its spell is otherwise kept, and SHALL NOT change the verdict of the spell's other ranks. A rank SHALL be named for a spec or for every spec of the class.

#### Scenario: Skipped rank of a kept spell
- **WHEN** a spell is kept by an override and rank 7 is skipped by the chosen revision
- **THEN** rank 7 is deferred and every other rank keeps its normal verdict

#### Scenario: Plain reason
- **WHEN** a skipped rank is shown to the player
- **THEN** the reason states the actual cause the revision records for that rank, in plain words without internal terms

#### Scenario: Revision decides
- **WHEN** revision 1 skips a rank that revision 2 does not
- **THEN** the rank is deferred on revision 1 and kept on revision 2

### Requirement: Player rule switches
The system SHALL let player settings switch off a single ability, a tag for a class, or a rule kind (skipped ranks, off-spec leaning, profession skill caps). Everything is on by default, so with no switch changed every verdict is that of the chosen skip revision.

#### Scenario: Switch stored
- **WHEN** the player switches off an ability and reloads the game
- **THEN** the ability is still switched off

#### Scenario: Switch under a later revision
- **WHEN** an ability was switched off before skip revisions existed
- **THEN** it is still switched off under every revision

### Requirement: Switch defaults
The system SHALL leave every verdict equal to the chosen skip revision's verdict while no switch has been touched.

#### Scenario: Defaults unchanged
- **WHEN** no switch has been touched and the player has chosen revision 1
- **THEN** every verdict equals the verdict before skip revisions existed

#### Scenario: Defaults on the newest revision
- **WHEN** no switch has been touched and no revision has been chosen
- **THEN** every verdict is the newest revision's verdict

## REMOVED Requirements

### Requirement: Rank skips come from expert guides
**Reason**: Revision 2 also skips ranks found by a computed review of the Forever spell data, so skips no longer come only from expert guides, and the single reason "only a small upgrade" no longer fits every skip. Where an expert guide has a view it still decides (see the rank-skip-revisions capability), and every skip records its source and true cause.
**Migration**: Revision 1 keeps the previous guide-sourced list. Revision 2's data labels each skip as guide-sourced, computed or inherited, and the player sees the reason that matches.
