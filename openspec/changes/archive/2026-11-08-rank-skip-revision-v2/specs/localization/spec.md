# Spec Delta

## ADDED Requirements

### Requirement: Skip reasons and the load notice are translatable
The system SHALL build every skip reason and the load notice from locale sentences keyed by their English text, with any numbers (a percentage, a rank, a revision) filled into the sentence rather than joined from translated fragments. The example locale file SHALL list every one of these sentences.

#### Scenario: Translated reason
- **WHEN** a locale file translates the sentence for "only the first rank is worth buying"
- **THEN** the trainer tooltip shows the translation with the spell's name in place

#### Scenario: Untranslated reason
- **WHEN** a locale file does not translate a skip reason
- **THEN** the English sentence is shown and no error is raised

#### Scenario: Example file
- **WHEN** a contributor opens the example locale file
- **THEN** it contains an entry for each skip reason sentence and each sentence of the load notice
