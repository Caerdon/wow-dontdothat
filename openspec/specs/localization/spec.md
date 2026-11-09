# localization Specification

## Purpose
Lets the addon's own text be translated by adding one file per language, falling back to English for anything untranslated, so contributors can add a language without touching code.

## Requirements

### Requirement: Text goes through a locale table
The system SHALL show every player-facing sentence (settings, warnings, tooltips, alerts, slash command replies) from a locale table keyed by its English text. Debug report text SHALL stay English.

#### Scenario: English client
- **WHEN** the client locale has no translation file
- **THEN** every sentence reads exactly as the English text

#### Scenario: Translated client
- **WHEN** a locale file translates a sentence
- **THEN** that sentence is shown in the translation

### Requirement: Missing translations fall back to English
The system SHALL show the English text for any sentence a locale file does not translate, and SHALL NOT raise an error.

#### Scenario: Partial translation
- **WHEN** a locale file translates only some sentences
- **THEN** the translated ones show in that language and the rest show in English

### Requirement: A language is added by one file
The system SHALL load a locale from a single file named for the client locale, with no code change, and SHALL document how to add one.

#### Scenario: New locale file
- **WHEN** a contributor adds a file for a locale and the client runs in it
- **THEN** its translations are used

### Requirement: Format placeholders are protected
The system SHALL keep each sentence with its values as one translatable unit, and a translation SHALL carry the same placeholders as its English key. A test SHALL fail on a translation key the source does not use, or on a mismatched placeholder count.

#### Scenario: Placeholder mismatch
- **WHEN** a translation has a different number of placeholders than its key
- **THEN** the test suite fails and names the key

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
