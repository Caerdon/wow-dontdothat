# Spec Delta

## ADDED Requirements

### Requirement: Skip reasons are accurate in the training window
The system SHALL show for a skipped rank, in the trainer window's tooltip and in the confirmation prompt, the reason that is true for it: what the guide says, a small step up for a spell used only now and then or one that does not repay its price, nothing gained over the rank before it, or a level 60 rank that can wait for the mount. It SHALL NOT name the data source there.

#### Scenario: Guide says first rank only
- **WHEN** the trainer lists Thunder Clap rank 3 and the guide advises only the first rank
- **THEN** the tooltip says the guide advises buying only the first rank of Thunder Clap

#### Scenario: Small step for an occasionally used spell
- **WHEN** a rank is skipped because it is 12% stronger than the previous rank for a spell the player only uses now and then
- **THEN** the tooltip says how much stronger it is and that the spell is only used now and then

#### Scenario: Small step for a core spell
- **WHEN** a rank is skipped because it is 8% stronger than the previous rank for a spell in the player's core rotation
- **THEN** the tooltip says how much stronger it is and that the gain does not repay its price, and does not say the spell is rarely used

#### Scenario: Nothing measurable
- **WHEN** a rank adds nothing measurable over the rank before it
- **THEN** the tooltip says it adds nothing over the rank before it

#### Scenario: Level 60 wait
- **WHEN** a later rank of a utility spell unlocks at level 60 and is skipped
- **THEN** the tooltip says it can wait until the level 60 mount

#### Scenario: Same words in the prompt
- **WHEN** the player is asked to confirm buying that rank
- **THEN** the question gives the same reason as the tooltip

#### Scenario: Earlier revision
- **WHEN** the player is on revision 1
- **THEN** each skipped rank's reason states the cause revision 1 records for it, not a reason it does not have
