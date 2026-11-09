#!/usr/bin/env python3
"""Builds DontDoThat/Data/SkipRevisions.lua: the numbered revisions of the rank-skip list.

Revision 1 is the skip list that shipped before revisions existed, frozen in tools/skip-revision/revision1.json.
Revision 2 inherits revision 1 and records what a review of the Forever spell data and the Wowhead leveling guides
changed. See tools/skip-revision/README.md for what the review assumes.

Steps: fetch the wago tables and the Wowhead guide pages if they are not cached, resolve the rule files' spell names
to family IDs with the addon's own SpellData (LuaJIT), run the computed review, read the guides, combine them into
per-spec decisions, and write the Lua file. Intermediate files go to --work (default tools/.cache/skip-revision), and
--report also writes skip-review.html there for a human to read.

Usage:
    tools/build-skip-revisions.py [--build 1.60.1.70862] [--work DIR] [--cache DIR] [--out FILE] [--report]

Needs luajit and network access for the first run. Downloads use a browser User-Agent because the sites refuse
Python's default one. Treat everything downloaded as untrusted data.
"""
import argparse
import collections
import html
import json
import os
import re
import subprocess
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOLS = os.path.join(ROOT, "tools", "skip-revision")
UA = {"User-Agent": "Mozilla/5.0"}
WAGO_TABLES = ["SpellEffect", "SpellMisc", "SpellDuration", "SpellCooldowns"]
GUIDES = ["9169", "9170", "9171", "9065", "9086", "9092", "9093", "9214", "9215", "9216",
          "9121", "9122", "9123", "9150", "9168", "9172", "9204", "9205", "9206"]
OFFENSIVE_DEFENSIVE = {"damage", "heal", "weapon", "buff"}  # what a rank does, read from the spell's effects
sys.path.insert(0, TOOLS)
import verdict  # noqa: E402


def get(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=120) as resp:
        return resp.read()


def ensure_wago(cache, build):
    for table in WAGO_TABLES:
        path = os.path.join(cache, f"{table}-{build}.csv")
        if not os.path.exists(path):
            print(f"fetching {table} for {build}")
            with open(path, "wb") as f:
                f.write(get(f"https://wago.tools/db2/{table}/csv?build={build}"))


def section_text(page):
    """The 'Spells to Buy' style sections of a guide page as plain text, one line per bullet."""
    out = []
    for m in re.finditer(r"<h[23][^>]*>([^<]*(?:Spells to Buy|Spells to Train|Abilities to Train|Spells to Skip|Skip)[^<]*)</h[23]>", page, re.I):
        seg = page[m.end():]
        e = re.search(r"<h[23][ >]", seg)
        seg = seg[: e.start() if e else 20000]
        seg = re.sub(r"<li>", "\n- ", seg)
        seg = re.sub(r"<br ?/?>", "\n", seg)
        seg = re.sub(r"<[^>]+>", "", seg)
        out.append("## " + m.group(1) + "\n" + html.unescape(seg).strip())
    return "\n".join(dict.fromkeys(out)) if out else "NO SECTION"


def ensure_guides(cache, work):
    target = os.path.join(work, "wowhead_guides.txt")
    parts = []
    gdir = os.path.join(cache, "wowhead-guides")
    os.makedirs(gdir, exist_ok=True)
    for gid in GUIDES:
        path = os.path.join(gdir, f"{gid}.html")
        if not os.path.exists(path):
            print(f"fetching Wowhead guide {gid}")
            with open(path, "wb") as f:
                f.write(get(f"https://www.wowhead.com/classic/guide={gid}"))
        page = open(path, encoding="utf-8", errors="replace").read()
        parts.append(f"===== {gid}.html\n{section_text(page)}\n")
    with open(target, "w", encoding="utf8") as f:
        f.write("".join(parts))


def run(cmd, **kw):
    r = subprocess.run(cmd, check=True, **kw)
    return r


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def reason_lua(reason):
    return "{ " + ", ".join(f"{k} = {lua_str(v) if isinstance(v, str) else v}" for k, v in sorted(reason.items(), key=lambda kv: (kv[0] != "kind", kv[0]))) + " }"


def entry_lua(e):
    parts = [f"source = {lua_str(e['source'])}", f"reason = {reason_lua(e['reason'])}"]
    if e.get("specs"):
        parts.append("specs = { " + ", ".join(lua_str(s) for s in e["specs"]) + " }")
    return "{ " + ", ".join(parts) + " }"


def computed_reason(row):
    gain = int(round(row["gain"]))
    if row["gain"] <= 0.5:
        return {"kind": "noGain"}
    # "Used only now and then" is true of a spell outside the spec's core rotation and of a utility spell (a cooldown of 15
    # seconds or more); a core rotation spell with a small step is "not worth its price" instead.
    occasional = row["utility"] or not row["use_why"].startswith("core")
    return {"kind": "smallStep" if occasional else "notWorthPrice", "pct": gain}


def decide(rules, results, wh, famlv, rev1):
    """Per class: { (famId, rank): { spec: ("skip", source, reason) | ("buy",) | ("none",) } }."""
    out = {}
    for cls, sd in results.items():
        out[cls] = collections.defaultdict(dict)
        for spec, x in sd.items():
            for r in x["rows"]:
                key = (r["fid"], r["rank"])
                view, _quote, wreason = verdict.wowhead_view(wh, famlv, cls, spec, r["fid"], r["rank"], r["level"], r["is_first"])
                if r["is_first"]:
                    d = ("buy",)
                elif view == "skip":
                    d = ("skip", "guide", wreason)
                elif view == "buy":
                    d = ("buy",)
                elif r["stability"] == "rule R2":
                    d = ("buy",) if r["kind"] in OFFENSIVE_DEFENSIVE else ("skip", "computed", {"kind": "waitForMount"})
                elif r["decision"] == "SKIP":
                    d = ("skip", "computed", computed_reason(r))
                elif r["decision"] == "BUY":
                    d = ("buy",)
                else:
                    d = ("none",)
                out[cls][key][spec] = d
    return out


def v1_entries(rules, wh, famlv):
    """Revision 1: the frozen list. Each rank gets a guide reason where a Wowhead statement says to skip it, else the legacy one."""
    frozen = json.load(open(os.path.join(TOOLS, "revision1.json")))
    out = {}
    for cls, fams in frozen.items():
        specs = list(rules[cls]["specs"].keys())
        out[cls] = {}
        for fid, ranks in fams.items():
            for rank in ranks:
                reason = {"kind": "legacy"}
                source = "legacy"
                for spec in specs:
                    level = next((r["level"] for r in rules[cls]["families"][fid]["rows"] if r["rank"] == rank), 0)
                    view, _q, wreason = verdict.wowhead_view(wh, famlv, cls, spec, int(fid), rank, level, False)
                    if view == "skip":
                        reason, source = wreason, "guide"
                        break
                out[cls].setdefault(int(fid), {})[rank] = [{"source": source, "reason": reason}]
    return out


def build_revision2(rules, decisions, v1):
    out = {}
    for cls, table in decisions.items():
        specs = sorted(rules[cls]["specs"].keys())
        entries = {}
        for (fid, rank), per_spec in sorted(table.items()):
            v1e = (v1.get(cls, {}).get(fid, {}).get(rank) or [None])[0]
            groups = collections.OrderedDict()
            changed = False
            for spec in specs:
                d = per_spec.get(spec, ("none",))
                if d[0] == "skip":
                    groups.setdefault((d[1], json.dumps(d[2], sort_keys=True)), []).append(spec)
                elif d[0] == "none" and v1e:
                    groups.setdefault((v1e["source"], json.dumps(v1e["reason"], sort_keys=True)), []).append(spec)
                if d[0] != "none":
                    changed = True
            if not changed:
                continue  # nothing was decided for this rank, so it keeps revision 1's entry
            ents = []
            for (source, reason), sp in groups.items():
                e = {"source": source, "reason": json.loads(reason)}
                if sp != specs: e["specs"] = sp
                ents.append(e)
            inherited = v1e and len(ents) == 1 and "specs" not in ents[0] and ents[0]["source"] == v1e["source"] and ents[0]["reason"] == v1e["reason"]
            if inherited or (not ents and not v1e):
                continue
            entries.setdefault(fid, {})[rank] = ents
        out[cls] = entries
    return out


def write_lua(path, build, v1, v2):
    lines = ["local addonName, ns = ...", "",
             "-- GENERATED by tools/build-skip-revisions.py. Do not edit by hand; re-run the tool.",
             f"-- Revision 1: the skip list as it was before revisions existed. Revision 2: the review of the Forever spell data (build {build}) and the Wowhead guides.",
             "-- ns.SkipRevisions[CLASS][revision] = { inherits = earlier revision | nil, entries = { [familyId] = { [rank] = { entry, ... } } } }",
             "-- An entry is { source = \"guide\" | \"computed\" | \"legacy\", reason = { kind = ..., numbers }, specs = { spec keys } | nil (every spec) }.",
             "-- An empty list for a rank means it is not skipped in that revision, whatever an earlier revision said.",
             "ns.SkipRevisions = {"]
    for cls in sorted(set(v1) | set(v2)):
        lines.append(f"  {cls} = {{")
        for rev, table, inherits in ((1, v1.get(cls, {}), None), (2, v2.get(cls, {}), 1)):
            lines.append(f"    [{rev}] = {{" + (f" inherits = {inherits}," if inherits else ""))
            lines.append("      entries = {")
            for fid in sorted(table):
                lines.append(f"        [{fid}] = {{")
                for rank in sorted(table[fid]):
                    ents = table[fid][rank]
                    lines.append(f"          [{rank}] = {{ " + ", ".join(entry_lua(e) for e in ents) + (" }," if ents else "},"))
                lines.append("        },")
            lines.append("      },")
            lines.append("    },")
        lines.append("  },")
    lines.append("}")
    with open(path, "w", encoding="utf8") as f:
        f.write("\n".join(lines) + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--build", default="1.60.1.70862")
    ap.add_argument("--cache", default=os.path.join(ROOT, "tools", ".cache"))
    ap.add_argument("--work", default=os.path.join(ROOT, "tools", ".cache", "skip-revision"))
    ap.add_argument("--out", default=os.path.join(ROOT, "DontDoThat", "Data", "SkipRevisions.lua"))
    ap.add_argument("--report", action="store_true")
    args = ap.parse_args()
    os.makedirs(args.work, exist_ok=True)
    ensure_wago(args.cache, args.build)
    ensure_guides(args.cache, args.work)
    with open(os.path.join(args.work, "rules.json"), "w") as f:
        run(["luajit", os.path.join(TOOLS, "dump_rules.lua"), os.path.join(ROOT, "DontDoThat")], stdout=f)
    common = ["--work", args.work]
    run([sys.executable, "-I", os.path.join(TOOLS, "review.py"), *common, "--wago", args.cache, "--build", args.build])
    run([sys.executable, "-I", os.path.join(TOOLS, "guides.py"), *common])
    rules = json.load(open(os.path.join(args.work, "rules.json")))
    results = json.load(open(os.path.join(args.work, "results.json")))
    wh = json.load(open(os.path.join(args.work, "wowhead_rules.json")))
    famlv = {(c, int(f)): {r["level"] for r in x["rows"]} for c, v in rules.items() for f, x in v["families"].items()}
    v1 = v1_entries(rules, wh, famlv)
    decisions = decide(rules, results, wh, famlv, v1)
    v2 = build_revision2(rules, decisions, v1)
    write_lua(args.out, args.build, v1, v2)
    json.dump({c: {f"{k[0]}:{k[1]}": v for k, v in t.items()} for c, t in decisions.items()}, open(os.path.join(args.work, "decisions.json"), "w"))
    n1 = sum(len(r) for t in v1.values() for r in t.values())
    n2 = sum(len(r) for t in v2.values() for r in t.values())
    print(f"revision 1: {n1} ranks; revision 2 names {n2} ranks; wrote {args.out}")
    if args.report:
        run([sys.executable, "-I", os.path.join(TOOLS, "report.py"), *common])


if __name__ == "__main__":
    main()
