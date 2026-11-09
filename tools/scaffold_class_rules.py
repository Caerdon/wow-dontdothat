#!/usr/bin/env python3
"""Writes DontDoThat/Rules/Data/<Class>.lua from tools/class_plans/<class>.py and the local spell cache.

Every spell family of the class (Forever and Classic Era, in the plan's skill lines) must end up somewhere:
in a rotation, a tag, an override, or the generated `reviewed` list. Names in the plan that are not real
families, and a spell that is both in a rotation and tagged, are reported and stop the run.
Rank skips are not written here: they live in Data/SkipRevisions.lua (tools/build-skip-revisions.py).

The generated names are resolved to spell IDs when the addon loads (see docs/rules-data.md). A name added to a plan
that the spell tables do not hold goes in tools/rule-spell-names.txt, then run tools/build-rule-spells.py.

Usage: tools/scaffold_class_rules.py CLASS [CLASS ...]      e.g. MAGE WARLOCK
"""
import importlib
import json
import os
import sys

BUILD = "1.60.1.70532"
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

OUT = os.path.join(HERE, "..", "DontDoThat", "Rules", "Data")


def q(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def lua_list(names, indent, width=104):
    lines, cur = [], ""
    for name in names:
        add = q(name) + ","
        if len(indent) + len(cur) + len(add) + 1 > width and cur:
            lines.append(indent + cur.rstrip())
            cur = ""
        cur += add + " "
    if cur.strip():
        lines.append(indent + cur.rstrip())
    return "\n".join(lines)


_acquire = {}


def _other_acquire(mask, lines_ok):
    """Spell families of a class whose every SkillLineAbility row has AcquireMethod 3 (not the ordinary trainer or
    level-up route; later-expansion and rune-style spells)."""
    import csv
    if "rows" not in _acquire:
        build = BUILD
        cache = os.path.join(HERE, ".cache")
        names = {r["ID"]: r["Name_lang"] for r in csv.DictReader(open(os.path.join(cache, f"SpellName-{build}.csv"), encoding="utf-8"))}
        lines = {r["ID"]: r["DisplayName_lang"] for r in csv.DictReader(open(os.path.join(cache, f"SkillLine-{build}.csv"), encoding="utf-8"))}
        _acquire["rows"] = [(int(r["ClassMask"] or 0), lines.get(r["SkillLine"], ""), names.get(r["Spell"], ""), r["AcquireMethod"])
                            for r in csv.DictReader(open(os.path.join(cache, f"SkillLineAbility-{build}.csv"), encoding="utf-8"))]
    methods = {}
    for m, line, name, method in _acquire["rows"]:
        if m & mask and line in lines_ok and name:
            methods.setdefault(name, set()).add(method)
    return {n for n, ms in methods.items() if ms == {"3"}}


def build(cls):
    plan = importlib.import_module("class_plans." + cls.lower()).PLAN
    data = json.load(open(os.path.join(HERE, ".cache", "class-spells.json")))["classes"][cls]
    lines_ok = set(plan["lines"])
    fams, era_fams, talents, problems = set(), set(), set(), []
    for tag in ("forever", "era"):
        for line, rows in data["spells"][tag].items():
            if line in lines_ok:
                fams |= {r[0] for r in rows}
                if tag == "era":
                    era_fams |= {r[0] for r in rows}
        for tab in data["talents"][tag].values():
            talents |= {t["name"] for t in tab}

    def expand(names):
        out = []
        for n in names:
            if n.startswith("~"):
                found = sorted(f for f in fams if f.startswith(n[1:]))
                if not found:
                    problems.append(f"no family starts with {n[1:]!r}")
                out += found
            else:
                if n not in fams and n not in talents:
                    problems.append(f"unknown spell {n!r}")
                out.append(n)
        return out

    core, sit = expand(plan["core"]), expand(plan["sit"])
    specs = []
    for key, name, tree, spec_core, spec_sit in plan["specs"]:
        specs.append((key, name, tree, [n for n in expand(spec_core) if n not in core], expand(spec_sit)))
    # Spells the game data says are not learned the ordinary way (every ability row has acquire method 3), and any
    # the plan lists as unverified, are Optional until a trainer capture confirms them: a core entry is demoted
    # to situational.
    # Interrupts and resurrections stay core whatever the data says about how they are learned.
    unverified = (_other_acquire(data["mask"], lines_ok) | set(plan.get("unverified", []))) - set(plan.get("always_core", []))
    demoted = sorted({n for n in core if n in unverified} | {n for s_ in specs for n in s_[3] if n in unverified})
    sit = sit + [n for n in core if n in unverified and n not in sit]
    core = [n for n in core if n not in unverified]
    specs = [(k, nm, tr, [n for n in sc if n not in unverified], ss + [n for n in sc if n in unverified and n not in ss])
             for k, nm, tr, sc, ss in specs]
    tags = {t: expand(ns) for t, ns in plan["tags"].items()}
    rotation = set(core) | set(sit) | {n for s in specs for n in s[3] + s[4]}
    for t, ns in tags.items():
        for n in ns:
            if n in rotation:
                problems.append(f"{n!r} is in a rotation and tagged {t}")
    overrides = plan.get("overrides", {})
    for n in list(overrides):
        if n not in fams:
            problems.append(f"unknown override {n!r}")
    why = dict(plan.get("why", {}))
    for prefix, text in plan.get("whyprefix", {}).items():
        for ns in tags.values():
            for n in ns:
                if n.startswith(prefix):
                    why.setdefault(n, text)

    classified = rotation | {n for ns in tags.values() for n in ns} | set(overrides)
    talent_spells = sorted((talents & fams) | (talents & classified))
    reviewed = sorted(fams - classified)

    L = ["local addonName, ns = ...\nlocal L = ns.L\n"]
    L += ["-- Source status: every rotation is a judgement call from common leveling builds, not a verified guide, so each",
          "-- carries needsReview = true. Spell names, levels, talents and tab order come from the game's own tables",
          "-- (WoW Forever 1.60.1.70532 and Classic Era 1.15.9.70003); what the trainer sells and what it charges are",
          "-- UNVERIFIED until a trainer is captured with /ddt export. Gold costs are left nil.",
          "-- Written by tools/scaffold_class_rules.py from tools/class_plans/" + cls.lower() + ".py.",
          "-- Every spell family must appear below (a rotation, a tag, an override or `reviewed`);",
          "-- tests/rules_classes_test.lua fails on any that does not.\n"]
    L += ["-- What every spec of this class keeps buying.", "local SHARED_CORE = {\n" + lua_list(core, "  ") + "\n}",
          "-- Handy now and then for any spec. The talent ones count only while the talent is active.",
          "local SHARED_SITUATIONAL = {\n" + lua_list(sit, "  ") + "\n}\n"]
    L.append("local function with(base, extra)\n  local out = {}\n  for _, name in ipairs(base) do out[#out + 1] = name end\n"
             "  for _, name in ipairs(extra) do out[#out + 1] = name end\n  return out\nend\n")
    L += ["ns.Rules.Load({", f'  class = "{cls}",\n', "  specs = {"]
    for key, name, tree, spec_core, spec_sit in specs:
        extra = "{ " + ", ".join(q(n) for n in spec_core) + " }" if spec_core else "{}"
        sit_expr = "with(SHARED_SITUATIONAL, { " + ", ".join(q(n) for n in spec_sit if n not in sit) + " })" if [n for n in spec_sit if n not in sit] else "SHARED_SITUATIONAL"
        L += [f"    {key} = {{", f"      name = L[{q(name)}], tree = {tree}, -- TalentTab order verified from the game tables",
              f"      rotation = {{ needsReview = true, core = with(SHARED_CORE, {extra}), situational = {sit_expr} }},", "    },"]
    L += ["  },\n", '  tagTiers = { PvP = "deferLow", RaidGroup = "defer", LowValue = "deferLow", Endgame = "defer" },\n',
          '  tagReasons = {\n    PvP = L["Mostly useful against other players."],\n    RaidGroup = L["Only needed in groups and raids."],\n'
          '    LowValue = L["Rarely helps while leveling."],\n    Endgame = L["You won\'t need this until level 60."],\n  },', "  why = {"]
    L += [f"    [{q(n)}] = L[{q(why[n])}]," for n in sorted(why)]
    L += ["  },\n", "  tags = {"]
    L += [f"    [{q(n)}] = {{ {q(t)} }}," for t, ns in tags.items() for n in ns]
    L += ["  },\n"]
    if overrides:
        L += ["  overrides = {"] + [f"    [{q(n)}] = {q(v)}," for n, v in overrides.items()] + ["  },\n"]
    L += ["  -- Active spells that come from a talent of the same name. Verified from the game's talent tables.",
          "  talentSpells = {\n" + lua_list(talent_spells, "    ") + "\n  },\n"]
    for key, what in (("general", "Skills that come with the class and are never trained, left off the Classes page."),
                      ("pet", "What a Pet Trainer teaches the pet, listed under Pet.")):
        if plan.get(key):
            L += [f"  -- {what}", f"  {key} = {{\n" + lua_list(sorted(plan[key]), "    ") + "\n  },\n"]
    if "grimoires" in plan:
        L.append(plan["grimoires"] + "\n")
    if "milestones" in plan:
        L.append(plan["milestones"] + "\n")
    L += ["  -- Considered and deliberately left at keep: passives, effects, racial and Forever-only spells whose use is not yet known.",
          "  reviewed = {\n" + lua_list(reviewed, "    ") + "\n  },", "})\n"]
    path = os.path.join(OUT, plan["file"] + ".lua")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(L))
    print(f"{cls}: {len(fams)} families, {len(classified)} classified, "
          f"{len(talent_spells)} talent spells, {len(reviewed)} reviewed -> {os.path.relpath(path)}")
    if demoted:
        print("  demoted to Optional (Forever-only or unverified): " + ", ".join(demoted))
    for p in problems:
        print(f"  PROBLEM: {p}")
    return not problems


if __name__ == "__main__":
    ok = all([build(c.upper()) for c in sys.argv[1:]])
    sys.exit(0 if ok else 1)
