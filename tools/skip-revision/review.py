#!/usr/bin/env python3
"""Computed review of every spell rank: what it costs in hours of grinding against what it gives back, per class and spec.

Reads the wago tables for one Forever build and the addon's own data files; writes results.json to --work.
Run by tools/build-skip-revisions.py; see tools/skip-revision/README.md for the assumptions below."""
import argparse, csv, json, re, itertools, collections, os, sys

_ap = argparse.ArgumentParser()
_ap.add_argument('--work', required=True)   # intermediate files (rules.json in, results.json out)
_ap.add_argument('--wago', required=True)   # directory of <Table>-<build>.csv files
_ap.add_argument('--build', required=True)  # e.g. 1.60.1.70862
_a = _ap.parse_args()
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
W, AN, B = _a.wago, _a.work, _a.build

# ---------- assumptions (all documented in the report) ----------
# Hours to play from level L to L+1. Source: LFCarry estimate quoted by kami-labs (Nov 2026):
# ~150h for 1-60: 20h for 1-20, 50h for 20-40, 80h for 40-60 (44h of it for 50-60 -> 4.4h/level).
def hours_at(L):
    if L < 20: return 1.0
    if L < 40: return 2.5
    if L < 50: return 3.6
    return 4.4
# Gold per hour (copper) from DontDoThat/Data/GoldRates.lua (estimates, needsReview).
def gph(L):
    for lo, v in reversed([(1,4000),(10,10000),(20,20000),(30,30000),(40,50000),(50,80000),(60,120000)]):
        if L >= lo: return v
# Spell power assumed on gear at level L (used only for coefficient scaling of effects).
def spell_power(L): return max(0, L - 10) * 1.5
USE_CORE, USE_SIT, USE_TAG, USE_OTHER, USE_PET = 0.30, 0.15, 0.02, 0.05, 0.15
CD_UTILITY_MS = 15000   # a spell with a >=15s cooldown is treated as utility/cooldown, not a rotation spell
USE_UTILITY_MULT = 0.10

SCEN = {  # (hours scale, gold-per-hour scale, use scale)
    'favor-skip': (0.65, 0.50, 0.60),
    'base':       (1.00, 1.00, 1.00),
    'favor-buy':  (1.35, 1.40, 1.50),
}

def rd(name):
    return csv.DictReader(open(f'{W}/{name}-{B}.csv', encoding='utf8'))

# ---------- load game tables ----------
effects = collections.defaultdict(list)
for r in rd('SpellEffect'): effects[int(r['SpellID'])].append(r)
dur_ms = {int(r['ID']): int(r['Duration']) for r in rd('SpellDuration')}
duration = {}
for r in rd('SpellMisc'):
    di = int(r['DurationIndex'] or 0)
    if di in dur_ms: duration[int(r['SpellID'])] = dur_ms[di]
cooldown = {}
for r in rd('SpellCooldowns'):
    t = max(int(r['RecoveryTime'] or 0), int(r['CategoryRecoveryTime'] or 0))
    sid = int(r['SpellID'])
    cooldown[sid] = max(cooldown.get(sid, 0), t)

DAMAGE, HEAL = {2}, {10}
WEAPON = {17, 31, 58, 121}
PERIODIC_DMG, PERIODIC_HEAL, ABSORB = 3, 8, 69
CC_AURAS = {5, 7, 12, 26, 27, 33, 31}   # fear, confuse, stun, root, etc. (flagged as duration spells)

def potency(sid, level, depth=0):
    """Returns (value, kind). kind in damage heal weapon buff duration none."""
    sp = spell_power(level)
    tot, kinds = 0.0, set()
    dur = duration.get(sid, 0) / 1000.0
    for e in effects.get(sid, []):
        eff = int(e['Effect']); aura = int(e['EffectAura'] or 0)
        base = abs(float(e['EffectBasePointsF'] or 0)); coef = float(e['EffectBonusCoefficient'] or 0)
        per = int(e['EffectAuraPeriod'] or 0)
        if eff in DAMAGE: tot += base + coef * sp; kinds.add('damage')
        elif eff in HEAL: tot += base + coef * sp; kinds.add('heal')
        elif eff in WEAPON: tot += base + 3.0 * level; kinds.add('weapon')
        elif eff == 6 and aura in (PERIODIC_DMG, PERIODIC_HEAL):
            ticks = (dur * 1000 / per) if per else 1
            tot += base * ticks + coef * sp; kinds.add('damage' if aura == PERIODIC_DMG else 'heal')
        elif eff == 6 and aura == ABSORB: tot += base + coef * sp; kinds.add('heal')
        elif eff == 6 and aura == 53: tot += base * ((dur * 1000 / per) if per else 1) + coef * sp; kinds.add('damage')
        elif eff == 6 and aura == 97: tot += base + coef * sp; kinds.add('heal')
        elif eff == 3 and not aura and base: tot += base + coef * sp; kinds.add('damage')
        elif eff == 6 and aura == 4 and base: tot += base + coef * sp; kinds.add('damage')
        elif eff == 6 and aura in (29, 13, 22, 35, 15, 8, 99, 101, 123, 142, 143, 189, 85, 79, 133, 674, 124, 127, 68, 138, 140, 137):
            if base: tot += base; kinds.add('buff')
        if int(e['EffectTriggerSpell'] or 0) and depth < 2 and (eff == 64 or aura in (23, 42)):
            tv, tk = potency(int(e['EffectTriggerSpell']), level, depth + 1)
            if tv > 0 and tk in ('damage', 'heal', 'weapon'):
                ticks = (dur * 1000 / per) if (per and aura == 23) else 1
                tot += tv * ticks; kinds.add(tk)
        elif eff == 6 and aura in CC_AURAS: kinds.add('duration')
    if tot > 0:
        k = 'weapon' if 'weapon' in kinds else ('damage' if 'damage' in kinds else ('heal' if 'heal' in kinds else 'buff'))
        return tot, k
    if dur > 0 and 'duration' in kinds: return dur, 'duration'
    return 0.0, 'none'

# ---------- spell families from SpellData.lua ----------
src = open(f'{REPO}/DontDoThat/Data/SpellData.lua').read()
parts = re.split(r'\n  ([A-Z]+) = \{', src)
fam = collections.defaultdict(lambda: collections.defaultdict(list))
cost_by_level = {}
pet_cost_by_level = {}
for i in range(1, len(parts), 2):
    cls, body = parts[i], parts[i + 1]
    if cls == 'HUNTER':
        m = re.search(r'costByLevel_class = \{(.*?)\}', body, re.S)
        cost_by_level = {int(a): int(b) for a, b in re.findall(r'\[(\d+)\] = (\d+)', m.group(1))}
        m = re.search(r'costByLevel_pet = \{(.*?)\}', body, re.S)
        pet_cost_by_level = {int(a): int(b) for a, b in re.findall(r'\[(\d+)\] = (\d+)', m.group(1))}

prices = {}
tp = open(f'{REPO}/DontDoThat/Data/TrainerPrices.lua').read()
for cm in re.finditer(r'\n  ([A-Z]+) = \{(.*?)\n  \},', tp, re.S):
    prices[cm.group(1)] = {int(a): int(b) for a, b in re.findall(r'\[(\d+)\] = (\d+)', cm.group(2))}

def level_lookup(table, lv):
    ks = [k for k in table if k <= lv]
    return table[max(ks)] if ks else (table[min(table)] if table else 0)

def price_for(cls, kind, rk):
    if rk['cost']: return rk['cost'], 'seen at trainer'
    p = prices.get(cls, {}).get(rk['id'])
    if p: return p, 'Wowhead trainer list'
    tbl = pet_cost_by_level if kind == 'pet' else cost_by_level
    return level_lookup(tbl, rk['level']), 'estimated from level'

rules = json.load(open(f'{AN}/rules.json'))   # spell IDs, resolved with the addon's own SpellData (dump_rules.lua)
for _cls, _v in rules.items():
    for _fid, _f in _v['families'].items():
        _kind = 'pet' if all(r['kind'] == 'pet' for r in _f['rows']) else 'class'
        fam[_cls][(int(_fid), _kind)] = [dict(id=r['id'], rank=r['rank'], level=r['level'], cost=r.get('cost')) for r in _f['rows']]
FAMNAME = {(c, int(f)): x['name'] for c, v in rules.items() for f, x in v['families'].items()}

CORE_SHARE = {}
def build_core_share():
    for cls, specs in rules.items():
        for spec, sd in specs['specs'].items():
            core = sd.get('core') or []
            pots = {}
            for (name, kind), rows in fam[cls].items():
                if name not in core or kind != 'class' or len(rows) < 1: continue  # name here is the family ID
                rows = sorted(rows, key=lambda r: r['rank']); last = rows[-1]
                v, k = potency(last['id'], 60)
                cd = max(cooldown.get(r['id'], 0) for r in rows)
                if k in ('damage', 'heal', 'weapon') and cd < CD_UTILITY_MS: pots[name] = v
            tot = sum(pots.values()) or 1.0
            CORE_SHARE[(cls, spec)] = {n: min(0.8, max(0.05, v / tot)) for n, v in pots.items()}

def spec_use(cls, spec, name):
    r = rules[cls]['specs'][spec]
    tags = (rules[cls].get('tags') or {}).get(str(name))
    if name in (r.get('core') or []):
        sh = CORE_SHARE.get((cls, spec), {}).get(name)
        if sh is not None: return sh, f'core rotation spell, about {sh*100:.0f}% of this spec\'s core damage/healing by rank power'
        return USE_CORE, 'core for this spec'
    if name in (r.get('sit') or []): return USE_SIT, 'situational for this spec'
    if tags: return USE_TAG, 'tagged ' + '/'.join(tags)
    return USE_OTHER, 'not in this spec\'s rotation'

def solve(ranks, use, hs, gs, us):
    """ranks: list of dicts with level,price,pot(level-> potency fn). Decide which ranks (2..n) to buy.
    Returns (bought set of indices, parts) minimizing lost-effective-hours + grind-hours."""
    n = len(ranks)
    H = []
    for i, r in enumerate(ranks):
        start = max(1, r['level'])
        end = ranks[i + 1]['level'] if i + 1 < n else 60
        H.append(hs * sum(hours_at(L) for L in range(start, max(end, start))))
    cost = [r['price'] / (gph(max(1, r['level'])) * gs) for r in ranks]
    U = use * us
    def loss_for(B):
        tot = 0.0
        for i, r in enumerate(ranks):
            held = max([b for b in B if b <= i] + [0])
            pi = r['pot'](r['level']) if True else 0
            ph = ranks[held]['pot_at'](r['level'])
            if pi > 0: tot += U * H[i] * max(0.0, 1 - ph / pi)
        return tot
    free = list(range(1, n))
    best = None
    for k in range(len(free) + 1):
        for comb in itertools.combinations(free, k):
            B = set(comb) | {0}
            obj = loss_for(B) + sum(cost[b] for b in comb)
            if best is None or obj < best[0] - 1e-12: best = (obj, B)
    return best[1], H, cost, loss_for

def analyse_family(cls, spec, name, kind, rows):
    rows = sorted(rows, key=lambda r: (r['rank'], r['level']))
    rows = [r for i, r in enumerate(rows) if i == 0 or r['rank'] != rows[i - 1]['rank']]  # a rank listed twice counts once
    use, use_why = spec_use(cls, spec, name)
    if kind == 'pet': use, use_why = max(use, USE_PET), 'pet ability'
    # exclude rank unlocking at level 60 (rule R2) from the optimisation
    opt = [r for r in rows if r['level'] < 60]
    out = []
    pot_kind = 'none'
    items = []
    for r in opt:
        sid = r['id']
        p, k = potency(sid, r['level'])
        pr, psrc = price_for(cls, kind, r)
        items.append(dict(r=r, price=pr, psrc=psrc, kind=k,
                          pot=(lambda sid=sid: (lambda L: potency(sid, L)[0]))(),
                          pot_at=(lambda sid=sid: (lambda L: potency(sid, L)[0]))()))
    kinds = [it['kind'] for it in items]
    pot_kind = max(set(kinds), key=kinds.count) if kinds else 'none'
    cd = max([cooldown.get(it['r']['id'], 0) for it in items] + [0])
    utility = cd >= CD_UTILITY_MS or pot_kind in ('duration', 'none')
    use_eff = use * USE_UTILITY_MULT if utility else use
    res = {}
    inconsistent = False
    for i in range(1, len(items)):
        a = items[i - 1]['pot'](items[i]['r']['level']); b = items[i]['pot'](items[i]['r']['level'])
        if a > 0 and b > 0 and b < 0.95 * a: inconsistent = True
    pots = [it['pot'](it['r']['level']) for it in items]
    if pots and any(v > 0 for v in pots) and any(v == 0 for v in pots): inconsistent = True  # some ranks have no measurable effect
    if inconsistent: pot_kind = 'none'
    if pot_kind == 'none' and len(items) >= 2:
        for i, it in enumerate(items):
            res[i] = dict(level=it['r']['level'], rank=it['r']['rank'], price=it['price'], psrc=it['psrc'], hours=0, gain=0, kind='none', use=round(use, 3), use_why=use_why, utility=True, cd=0, id=it['r']['id'], decision='UNSCORED', stability='no data', cost_h=0, benefit_h=0, inconsistent=inconsistent)
    elif len(items) >= 2:
        flatten = []
        for it in items:
            flatten.append(dict(level=it['r']['level'], price=it['price'], pot=it['pot'], pot_at=it['pot_at']))
        scen_buy = {}
        for sc, (hs, gs, us) in SCEN.items():
            B, H, cost, loss = solve(flatten, use_eff, hs, gs, us)
            scen_buy[sc] = B
        Bb, Hb, costb, lossb = solve(flatten, use_eff, *SCEN['base'])
        Ub = use_eff * SCEN['base'][2]
        for i, it in enumerate(items):
            held = max([b for b in Bb if b < i] + [0])
            ph = items[held]['pot_at'](it['r']['level']); pi = it['pot'](it['r']['level'])
            gain = (pi / ph - 1) if ph > 0 else 0.0
            rec = dict(level=it['r']['level'], rank=it['r']['rank'], price=it['price'], psrc=it['psrc'],
                       hours=round(Hb[i], 2), gain=round(gain * 100, 1), kind=it['kind'], use=round(use_eff, 3),
                       use_why=use_why, utility=utility, cd=cd // 1000, id=it['r']['id'])
            if i == 0:
                rec.update(decision='BUY', stability='first rank', reason='First rank of the spell: you learn it when you first want the spell.', cost_h=0.0, benefit_h=0.0)
            else:
                decs = {sc: (i in B) for sc, B in scen_buy.items()}
                dec = 'BUY' if decs['base'] else 'SKIP'
                if all(decs.values()): stab = 'BUY stable'
                elif not any(decs.values()): stab = 'SKIP stable'
                else: stab = 'flips with assumptions'
                B_with = set(Bb) | {i}; B_wo = set(Bb) - {i}
                ben = lossb(B_wo) - lossb(B_with)
                rec.update(decision=dec, stability=stab, cost_h=round(costb[i], 2), benefit_h=round(ben, 2))
                rec['decs'] = decs
            res[i] = rec
    out = [res[i] for i in sorted(res)]
    # level-60 ranks
    for r in rows:
        if r['level'] >= 60:
            pr, psrc = price_for(cls, kind, r)
            out.append(dict(level=60, rank=r['rank'], price=pr, psrc=psrc, hours=0, gain=0, kind=pot_kind, use=round(use_eff, 3),
                            use_why=use_why, utility=utility, cd=cd // 1000, id=r['id'], decision='SKIP', stability='rule R2',
                            cost_h=0, benefit_h=0, reason=''))
    return out

def fmt_g(c):
    g, s = divmod(int(c), 10000)
    s, cu = divmod(s, 100)
    return (f'{g}g ' if g else '') + (f'{s}s ' if s else '') + (f'{cu}c' if cu and not g else '') or '0'

def reason(rec, name, held_rank, spec_name):
    if rec['stability'] == 'first rank': return rec['reason']
    if rec['stability'] == 'no data':
        if rec.get('inconsistent'): return 'In the game data this spell\'s ranks do not get steadily stronger (a later rank measures weaker than an earlier one), so the model cannot trust its numbers. Left to expert guides.'
        return 'The game data shows no measurable damage, healing, buff or duration change between ranks of this spell, so the model cannot score it. Left to expert guides.'
    if rec['stability'] == 'rule R2':
        return ('Unlocks at level 60. You will not be earning meaningful gold for it until after your level 60 mount, so wait; '
                'it is also often not sold at the trainer.')
    why = []
    why.append(f"{rec['use_why']} (use weight {rec['use']:.2f})" + (', a cooldown/utility spell so its use is discounted' if rec['utility'] and rec['kind'] not in ('duration','none') else ''))
    kind_txt = {'damage': 'damage', 'heal': 'healing', 'weapon': 'weapon-based damage (low confidence)', 'buff': 'buff strength', 'duration': 'effect duration only', 'none': 'no measurable power change in the game data'}[rec['kind']]
    g = f"This rank is +{rec['gain']}% over rank {held_rank} you would otherwise keep ({kind_txt}). " if rec['gain'] > 0 else f"This rank adds nothing measurable over rank {held_rank} ({kind_txt}). "
    price = f"Costs {fmt_g(rec['price'])} ({rec['psrc']}) = {rec['cost_h']}h of grinding. "
    time = f"You would spend about {rec['hours']}h at this rank before the next one unlocks. "
    ben = f"Having it recovers about {rec['benefit_h']}h of effective play. "
    verdict = ('BUY: the benefit is larger than the cost.' if rec['decision'] == 'BUY' else 'SKIP: the cost is larger than the benefit.')
    return ' '.join([g, time, price, ben, '; '.join(why) + '.', verdict]).replace('  ', ' ')

def main():
    build_core_share()
    out = {}
    for cls, specs in rules.items():
        out[cls] = {}
        for spec in specs['specs']:
            rows_out = []
            for (name, kind), rows in sorted(fam[cls].items()):
                if len(rows) < 2: continue
                fid = name; name = FAMNAME[(cls, fid)]
                recs = analyse_family(cls, spec, fid, kind, rows)
                held = {}
                first_rank = min(r['rank'] for r in rows)
                for rec in recs:
                    rec['is_first'] = rec['rank'] == first_rank
                    rec['spell'] = name; rec['fid'] = fid
                    rec['pet'] = kind == 'pet'
                # held rank for explanation: nearest earlier BUY
                last_buy = 1
                for rec in recs:
                    rec['reason'] = reason(rec, name, last_buy, spec)
                    if rec['decision'] == 'BUY': last_buy = rec['rank']
                rows_out.extend(recs)
            out[cls][spec] = dict(name=specs['specs'][spec].get('name', spec), rows=rows_out)
    # mark existing skips
    for cls, d in out.items():
        sk = rules[cls].get('skipRanks') or {}
        for spec, sd in d.items():
            for rec in sd['rows']:
                rec['current_skip'] = rec['rank'] in (sk.get(str(rec['fid'])) or [])
    json.dump(out, open(f'{AN}/results.json', 'w'))
    n = sum(len(sd['rows']) for d in out.values() for sd in d.values())
    print('rows', n)

if __name__ == '__main__':
    main()
