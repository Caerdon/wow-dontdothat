# rule-engine Specification

## Purpose
Decides whether a proposed gold-spending action is advisable before the player's active mount milestone, and explains why. It turns rule data and player state into a verdict that every other capability consumes.

## Requirements

### Requirement: Verdict for a proposed action
The system SHALL evaluate a proposed action against the player's profile and return a verdict containing a tier, an estimated cost in copper, a reason, and the milestone the saving applies to.

#### Scenario: Flagged action
- **WHEN** a Hunter below level 40 evaluates training a spell that the rules mark as deferred
- **THEN** the verdict has a non-"keep" tier, a cost, a reason, and the level 40 milestone

#### Scenario: Unknown action
- **WHEN** an action matches no rule or tag
- **THEN** the verdict is "keep" and no warning is produced

### Requirement: Tiers
The system SHALL support four tiers: keep (no warning), informational (badge and tooltip), defer-low-value (badge and tooltip, never a confirmation prompt), and defer (badge, tooltip, and a confirmation prompt where interception is possible).

#### Scenario: Defer-low-value never prompts
- **WHEN** an action is evaluated as defer-low-value
- **THEN** the verdict does not request a confirmation prompt

### Requirement: Rotation-derived verdicts
The system SHALL treat an ability in a core list of any relevant spec's rotation as keep, an ability in a situational list as informational, and an ability in no relevant spec's lists as eligible for tag-based tiers. An ability that the rule data marks as requiring a talent SHALL count as being in a rotation list only while that talent is active; otherwise it SHALL be evaluated as if it were in no rotation list.

#### Scenario: Core ability
- **WHEN** Serpent Sting is in the core list of a relevant spec
- **THEN** the verdict is "keep"

#### Scenario: Ability used only by another spec
- **WHEN** an ability appears only in the rotation of a spec that is not among the player's relevant specs
- **THEN** it is evaluated by its tags instead of being kept

#### Scenario: Talent spell without its talent
- **WHEN** a Marksmanship Hunter has not taken the talent that grants Aimed Shot and Aimed Shot is in the core list of a relevant spec
- **THEN** it is not kept because of that list and is evaluated by its tags and later rules instead

#### Scenario: Talent spell with its talent
- **WHEN** the same Hunter has taken the talent
- **THEN** Aimed Shot is kept because of the core list

### Requirement: Tag defaults
The system SHALL map ability tags to default tiers, with PvP-tagged abilities defaulting to defer-low-value and raid or group-utility-tagged abilities defaulting to defer.

#### Scenario: PvP default
- **WHEN** an ability tagged PvP has no override and is in no relevant rotation
- **THEN** the verdict is defer-low-value

### Requirement: Rule data is separate from engine logic
The system SHALL load all class, spec, profession, tag, override, and cost rules from data files, so that adding a class or profession requires adding data without changing engine logic.

#### Scenario: Adding a class
- **WHEN** a new class data file is added with rotations and tags
- **THEN** the engine evaluates that class's actions without code changes

### Requirement: Human-readable reasons
The system SHALL provide for every non-keep verdict a reason that names the cause, such as the spec or tag involved or the rank that supersedes it.

#### Scenario: Spec-specific reason
- **WHEN** a Survival melee ability is flagged for a Beast Mastery player
- **THEN** the reason states it is a Survival ability and the player's tree split

### Requirement: Rotation data review status
The system SHALL allow rotation data to be marked "needs review" and SHALL display that status wherever the rules are shown.

#### Scenario: Unreviewed rotation
- **WHEN** a spec's rotation is flagged "needs review"
- **THEN** the Rules page labels it as such

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

### Requirement: Spec override
The system SHALL use a spec the player picked for a class as that class's only plausible spec, in place of inference from talents. A pick that is not one of the class's specs SHALL be ignored.

#### Scenario: Override replaces inference
- **WHEN** the player picks Beast Mastery and the talents lean Marksmanship
- **THEN** only Beast Mastery counts as the player's spec

#### Scenario: Automatic
- **WHEN** no spec is picked for the class
- **THEN** the spec is inferred from talents as before

#### Scenario: Unknown pick
- **WHEN** the saved pick names a spec the class data does not have
- **THEN** the spec is inferred from talents

### Requirement: Paladin rules
The system SHALL support Paladins with the same verdict tiers as other classes, with a spec for each of Holy, Protection and Retribution. It SHALL keep Seals, Judgement, Holy Light, Flash of Light and Blessing of Might for every Paladin spec, keep Seal of Command only while its talent is active, and defer utility, PvP and group spells until the player no longer needs to save for a mount.

#### Scenario: Core Paladin spells
- **WHEN** a Paladin evaluates Seal of Righteousness, Judgement, Holy Light, Flash of Light or Blessing of Might
- **THEN** the verdict is "keep"

#### Scenario: Utility and group spells
- **WHEN** a Paladin evaluates Lay on Hands or a resistance aura
- **THEN** the verdict is a defer tier with a plain-language reason

#### Scenario: Turn Undead
- **WHEN** a Paladin evaluates Turn Undead
- **THEN** the verdict is defer-low-value

#### Scenario: Talent spell
- **WHEN** a Paladin who has not taken the Seal of Command talent evaluates it
- **THEN** it is not kept because of a rotation list

#### Scenario: Unreviewed rotations
- **WHEN** a Paladin spec's rotation has not been reviewed against a source
- **THEN** the rotation is flagged "needs review" wherever the rules are shown

#### Scenario: Every Paladin spell is considered
- **WHEN** the bundled Paladin spell table lists a spell family
- **THEN** the Paladin rule data places it in a rotation, a tag, an override, or a reviewed-and-kept list, and a check fails if one is missing

#### Scenario: Protection talent spells
- **WHEN** a Protection Paladin has taken the Holy Shield talent and evaluates it
- **THEN** it is kept as part of the Protection rotation

### Requirement: Rules for the remaining classes
The system SHALL support Mage, Warlock, Priest, Druid, Shaman, Rogue and Warrior with the same verdict tiers as Hunter and Paladin, with one spec per talent tree in the game's tab order, and SHALL place every spell family in their game tables in a rotation, a tag, an override or a reviewed-and-kept list. Spec rotations SHALL be flagged "needs review" until checked against a source.

#### Scenario: Spec-aware spells
- **WHEN** a Frost mage with the Frost talents evaluates Fireball
- **THEN** it is not kept for a rotation and is judged as mostly used by another spec

#### Scenario: Undecided talents keep everything
- **WHEN** a mage with no talent points spent evaluates Fireball and Frostbolt
- **THEN** both are kept

#### Scenario: Skipped spells
- **WHEN** a mage evaluates Dampen Magic or Scorch
- **THEN** the verdict is defer-low-value with a plain-language reason

#### Scenario: Talent spells
- **WHEN** a mage who has not taken the Ice Barrier talent evaluates it
- **THEN** it is not kept because of a rotation list

#### Scenario: Every spell is considered
- **WHEN** a bundled class table lists a spell family
- **THEN** the class rule data places it somewhere, and a check fails if one is missing

### Requirement: Save gold as a Warlock or Paladin
The system SHALL treat the spells in the expert guides' recommended lists (Icy Veins' "Recommended Skills to Upgrade" and Wowhead's spec guides) as worth buying for Warlocks and Paladins, and SHALL list the spells those guides do not mention as not worth buying yet, even though both classes get a free level 40 mount, because the aim is still to save gold. It SHALL keep a Warlock demon's grimoire unflagged when the guides recommend it, and flag the other grimoires.

#### Scenario: Recommended Paladin spell
- **WHEN** a Paladin of any spec evaluates Lay on Hands, Blessing of Protection, Blessing of Freedom or Divine Intervention
- **THEN** it is kept

#### Scenario: Unrecommended Paladin spell
- **WHEN** a Paladin evaluates Exorcism, Holy Wrath or Blessing of Kings
- **THEN** the verdict is defer-low-value

#### Scenario: Optional by the guides' own words
- **WHEN** a Paladin evaluates Devotion Aura
- **THEN** it is listed as optional, since the guide says it can be skipped to save gold

#### Scenario: Recommended Warlock spell
- **WHEN** a Warlock evaluates Ritual of Summoning, Unending Breath, Howl of Terror, Death Coil or Inferno
- **THEN** it is kept

#### Scenario: Unrecommended Warlock spell
- **WHEN** a Warlock evaluates Searing Pain, Soul Fire, Banish or Create Firestone
- **THEN** the verdict is defer-low-value

#### Scenario: Hammer of Justice ranks
- **WHEN** a Paladin evaluates Hammer of Justice rank 2
- **THEN** the verdict is defer, because Icy Veins says to take just rank 1

### Requirement: Resurrections and interrupts are worth buying
The system SHALL treat every single-target resurrection spell and every interrupt as worth buying for every spec of its class, whatever the player's talents lean toward, and SHALL NOT list one as optional, low value or waiting. Where an interrupt comes from a talent, it counts only while the talent is active.

#### Scenario: Resurrection
- **WHEN** a druid, priest, paladin or shaman of any spec evaluates their single-target resurrection
- **THEN** it is kept

#### Scenario: Interrupt
- **WHEN** a mage, rogue, warrior or Shadow priest evaluates Counterspell, Kick, Pummel, Shield Bash or Silence
- **THEN** it is kept (Silence once its talent is active)

### Requirement: Unverified spells are optional
The system SHALL list a spell that the game data shows is not learned the ordinary way, or that has not been confirmed at a real trainer, as optional rather than worth buying until it is confirmed, except for interrupts and resurrections.

#### Scenario: Forever-only spell
- **WHEN** a druid evaluates Savage Roar
- **THEN** it is listed as optional

### Requirement: Leveling-based spell assessment
The system SHALL judge every class's spells by how they are used in common leveling builds: a spell a leveling spec relies on is kept for that spec, a spell only other specs use is judged as mostly used by them, a spell nobody levels with is defer-low-value, and group, raid, PvP and level 60 spells wait. A spell the brief calls skippable SHALL still be kept for the specs that use it.

#### Scenario: Smite for a Holy priest
- **WHEN** a Holy priest evaluates Smite
- **THEN** it is kept

#### Scenario: Smite for a Shadow priest
- **WHEN** a Shadow priest evaluates Smite
- **THEN** it is judged as mostly used by other specs

#### Scenario: Thunder Clap for an Arms warrior
- **WHEN** an Arms warrior evaluates Thunder Clap
- **THEN** it is kept

#### Scenario: Undecided talents
- **WHEN** a player has spent no talent points
- **THEN** every spell any spec keeps is kept

### Requirement: Evaluation order
The system SHALL resolve a verdict in this order: explicit rank skip, explicit per-action override, spec-aware rotation membership, ability tags, then keep. The first rule that applies SHALL decide the verdict.

#### Scenario: Override beats tag
- **WHEN** an ability is tagged PvP but has an explicit "keep" override
- **THEN** the verdict is "keep"

#### Scenario: Skipped rank beats the rotation
- **WHEN** a rank of a core spell is in the skip list
- **THEN** that rank is deferred and the spell's other ranks keep their verdict

### Requirement: Switch order
A switched-off ability SHALL get a keep verdict before any other rule is considered. A switched-off tag SHALL be evaluated as if the ability did not carry it. A switched-off rule kind SHALL be skipped, and evaluation continues to the next rule.

#### Scenario: Ability off
- **WHEN** an ability is switched off and it would otherwise be flagged by any rule
- **THEN** the verdict is "keep"

#### Scenario: Tag off
- **WHEN** an ability is flagged only by a PvP tag and the PvP tag is switched off
- **THEN** evaluation continues past the tag rule and, if nothing else applies, the verdict is "keep"

#### Scenario: Rule kind off
- **WHEN** skipped ranks are switched off
- **THEN** a rank in the skip list is not flagged

### Requirement: Profession margin setting
The system SHALL take the profession near-cap margin from player settings when set, and from rule data otherwise. Values SHALL be whole numbers of zero or more; anything else is ignored and the rule data value is used.

#### Scenario: Tighter margin
- **WHEN** the player sets the near-cap margin to 10 and the skill is 15 below the cap
- **THEN** the profession tier is flagged

#### Scenario: Invalid value
- **WHEN** a setting holds a negative or non-numeric value
- **THEN** the rule data value is used

### Requirement: Spells are identified by spell ID
The system SHALL identify a spell by the spell ID of its family, not by its displayed name, so a verdict is the same whatever language the client runs in. A trainer row SHALL be matched to its spell by the spell ID the game gives for the row, and only when the game gives none by the displayed name and the numbers in its rank text.

#### Scenario: Non-English client
- **WHEN** a trainer lists a spell under a name that differs from the English one
- **THEN** the row receives the same verdict as on an English client

#### Scenario: Same name, different spells
- **WHEN** two spells of different classes or pets share a name
- **THEN** each is judged by its own rules

### Requirement: Rule data is checked against the spell tables
The system SHALL accept rule data written with spell names only when every name resolves to a spell in the bundled spell tables, and the test suite SHALL fail on a name that does not.

#### Scenario: Misspelled name
- **WHEN** a rule lists a name that matches no spell
- **THEN** the test suite fails and names the rule and the spell

### Requirement: Talents and professions match without English text
The system SHALL decide which talents are active and which profession a lesson belongs to without comparing English text.

#### Scenario: First lesson in a non-English client
- **WHEN** the player is offered the apprentice lesson of a new profession
- **THEN** it is recognized as that profession's first lesson

#### Scenario: Active talent in a non-English client
- **WHEN** a rotation spell needs a talent the player has
- **THEN** the talent counts as active
