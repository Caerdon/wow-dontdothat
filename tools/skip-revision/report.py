#!/usr/bin/env python3
import json, os, sys, html, collections
import argparse
_ap = argparse.ArgumentParser(); _ap.add_argument('--work', required=True); AN = _ap.parse_args().work
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import verdict
d = json.load(open(f'{AN}/results.json'))
OUT = AN
os.makedirs(OUT, exist_ok=True)

def money(c):
    g, r = divmod(int(c), 10000); s, cu = divmod(r, 100)
    return (f'{g}g ' if g else '') + (f'{s}s ' if s else '') + (f'{cu}c' if cu and not g else '') or '0c'

WH = json.load(open(f'{AN}/wowhead_rules.json'))
RULES2 = json.load(open(f'{AN}/rules.json'))
FAMLV = {(c, int(f)): {r['level'] for r in x['rows']} for c, v in RULES2.items() for f, x in v['families'].items()}
def wh_verdict(cls, spec, fid, rank, level, stability):
    v, q, _ = verdict.wowhead_view(WH, FAMLV, cls, spec, fid, rank, level, stability == 'first rank')
    return v, q

CLASSNAMES = {'DRUID': 'Druid', 'HUNTER': 'Hunter', 'MAGE': 'Mage', 'PALADIN': 'Paladin', 'PRIEST': 'Priest', 'ROGUE': 'Rogue', 'SHAMAN': 'Shaman', 'WARLOCK': 'Warlock', 'WARRIOR': 'Warrior'}
data = []
for cls, specs in d.items():
    for skey, sd in specs.items():
        rows = []
        for r in sorted(sd['rows'], key=lambda r: (r['level'], r['spell'], r['rank'])):
            cur = r['current_skip']; dec = r['decision']; st = r['stability']; reason = r['reason']
            whv, whtext = wh_verdict(cls, skey, r['fid'], r['rank'], r['level'], st)
            whdis = ''
            if whv:
                final = 'BUY' if whv == 'buy' else 'SKIP'
                model_says = 'hold it until the level 60 mount' if st == 'rule R2' else ('make no call' if dec == 'UNSCORED' else dec)
                differs = (dec == 'UNSCORED') or (st == 'rule R2' and whv == 'buy') or (st != 'rule R2' and dec != final)
                if dec == 'UNSCORED': whdis = 'filled'
                elif differs: whdis = 'override'
                else: whdis = 'agree'
                reason = f"Wowhead decides this one: {whtext} So: {final}. "
                if whdis == 'override': reason += f"The model's own calculation said to {model_says.lower() if model_says.startswith(('hold','make')) else model_says}, but Wowhead's view is used instead. (Model: {r['reason']})"
                elif whdis == 'filled': reason += 'The game data gave the model nothing to score for this spell.'
                else: reason += 'The model agrees.'
                dec = final; st = 'Wowhead'
            if st == 'rule R2': delta = 'level60-agree' if cur else 'level60'
            elif dec == 'UNSCORED': delta = 'unscored'
            elif cur and dec == 'SKIP': delta = 'agree'
            elif cur and dec == 'BUY': delta = 'model-buys'
            elif (not cur) and dec == 'SKIP': delta = 'model-skips'
            else: delta = 'agree'
            whcur = ''
            if whv == 'buy' and cur: whcur = 'cur'
            elif whv == 'skip' and not cur and r['stability'] != 'first rank': whcur = 'cur'
            rows.append([r['level'], r['spell'], r['rank'], dec, st, money(r['price']), r['psrc'], r['hours'], r['gain'], r['use'],
                         r['benefit_h'], r['cost_h'], 1 if cur else 0, delta, reason, r['kind'], 1 if r.get('pet') else 0, whv or '', whdis, whcur, whtext])
        data.append(dict(cls=cls, clsName=CLASSNAMES[cls], spec=skey, specName=sd['name'], rows=rows))

summary = collections.Counter()
for sd in data:
    for r in sd['rows']: summary[r[13]] += 1

page = """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Rank skip review</title>
<style>
:root{--bg:#fafafa;--fg:#1d1f23;--mut:#666c75;--card:#fff;--line:#e2e4e8;--buy:#1c7c3a;--buybg:#e4f4ea;--skip:#b3261e;--skipbg:#fbe9e7;--un:#555;--unbg:#eceff1;--warn:#a15c00;--acc:#2158d6}
@media (prefers-color-scheme:dark){:root{--bg:#15171a;--fg:#e8eaed;--mut:#9aa1ab;--card:#1e2126;--line:#33373d;--buy:#7fd69a;--buybg:#1c3326;--skip:#ff9a92;--skipbg:#3b2220;--un:#b0b6bf;--unbg:#2a2e34;--warn:#f0b24a;--acc:#8fb0ff}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:14px/1.45 system-ui,sans-serif}
main{max-width:1400px;margin:0 auto;padding:20px 16px 80px}
h1{font-size:22px;margin:0 0 4px}h2{font-size:16px;margin:24px 0 8px}
p,li{color:var(--fg)}.mut{color:var(--mut)}
.card{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:12px 16px;margin:12px 0}
.tabs{display:flex;flex-wrap:wrap;gap:6px;margin:12px 0}.tabs button,.ctl button{background:var(--card);color:var(--fg);border:1px solid var(--line);border-radius:6px;padding:6px 12px;cursor:pointer;font:inherit}
.tabs button.on{background:var(--acc);color:#fff;border-color:var(--acc)}
.ctl{display:flex;flex-wrap:wrap;gap:12px;align-items:center;margin:8px 0}.ctl label{display:flex;gap:4px;align-items:center}
input[type=search]{padding:6px 10px;border:1px solid var(--line);border-radius:6px;background:var(--card);color:var(--fg);min-width:200px}
table{width:100%;border-collapse:collapse;background:var(--card)}th,td{padding:6px 8px;border-bottom:1px solid var(--line);vertical-align:top;text-align:left}
th{position:sticky;top:0;background:var(--card);font-size:12px;color:var(--mut);z-index:1}
td.n{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}
.pill{display:inline-block;border-radius:10px;padding:1px 8px;font-weight:600;font-size:12px;white-space:nowrap}
.BUY{background:var(--buybg);color:var(--buy)}.SKIP{background:var(--skipbg);color:var(--skip)}.UNSCORED{background:var(--unbg);color:var(--un)}
.flip{color:var(--warn);font-size:12px}.tag{font-size:11px;border:1px solid var(--line);border-radius:4px;padding:0 5px;margin-left:4px;color:var(--mut)}
.reason{max-width:640px;color:var(--mut);font-size:13px}
tr.dis td:first-child{box-shadow:inset 3px 0 var(--warn)}
tr.hide{display:none}
@media (max-width:800px){table{display:block;overflow-x:auto}}
.legend span{margin-right:14px}
</style></head><body><main>
<h1>Rank skip review</h1>
<p class="mut">Which spell ranks to buy or skip, calculated from game data (WoW: Forever build 1.60.1.70862), per class and spec, sorted by level. Nothing here is applied to the addon.</p>
<div class="card"><b>How each decision is made.</b> For every rank we compare two numbers, both in hours of play:
<ul>
<li><b>Cost</b>: the trainer price divided by gold earned per hour at that level (the addon's own gold-rate table).</li>
<li><b>Benefit</b>: (how much stronger this rank is than the rank you would otherwise keep) &times; (how much of your play the spell is used) &times; (hours you spend before the next rank unlocks).</li>
<li><b>BUY</b> when benefit is larger than cost, otherwise <b>SKIP</b>. The best set of buys for each spell is solved together, so skipping one rank changes the value of the next.</li>
<li>Hours per level (LFCarry estimate quoted by kami-labs, Nov 2026): about 1h/level for 1-20, 2.5h for 20-40, 3.6h for 40-50 and 4.4h for 50-60, 150h total.</li>
<li><b>Use</b>: a core spell gets its share of the spec's core damage/healing by rank power; situational spells 0.15, tagged low-value 0.02, anything else 0.05; spells with a cooldown of 15s or more (utility) are discounted by 90%. Pet abilities 0.15.</li>
<li><b>Ranks that unlock at level 60</b> are held until you have your level 60 mount (rule R2) unless Wowhead says to train them; many are not sold by the trainer.</li>
<li><b>Stability</b>: each decision is re-run with faster/slower leveling, richer/poorer gold, and higher/lower use. <b>BUY stable</b> and <b>SKIP stable</b> never change; <span class="flip">flips with assumptions</span> changes, so look at those yourself.</li>
<li><b>UNSCORED</b>: the game data shows no measurable damage, healing, buff or duration difference between ranks, so the model makes no call.</li>
</ul>
<p class="mut">Weapon-based abilities are marked low confidence because their weapon damage is not in the spell record. Prices marked "estimated" come from a level-based table.</p></div>
<div class="card" id="valcard"></div>
<div class="tabs" id="ctabs"></div><div class="tabs" id="stabs"></div>
<div class="ctl">
<input type="search" id="q" placeholder="Search spell">
<label><input type="checkbox" id="fskip">Only SKIP</label>
<label><input type="checkbox" id="fdis">Only disagreements with current data</label>
<label><input type="checkbox" id="fflip">Only flips</label>
<label>Wowhead <select id="fwh"><option value="all">all rows</option><option value="override">Wowhead overrode the model</option><option value="filled">Wowhead filled in (model had no call)</option><option value="cur">Wowhead differs from the current skip list</option><option value="any">any Wowhead decision</option></select></label>
<label><input type="checkbox" id="fno60" checked>Hide level 60 rule rows</label>
<label><input type="checkbox" id="funs" checked>Hide unscored</label>
<span class="mut" id="count"></span>
</div>
<div class="legend mut"><span><span class="pill BUY">BUY</span> buy it</span><span><span class="pill SKIP">SKIP</span> skip it</span><span>amber bar = differs from the addon's current skip list</span></div>
<table><thead><tr><th>Lvl</th><th>Spell</th><th>Rank</th><th>Decision</th><th>Wowhead says</th><th>Price</th><th class="n">Hours at rank</th><th class="n">Stronger by</th><th class="n">Use</th><th class="n">Benefit h</th><th class="n">Cost h</th><th>Why</th></tr></thead><tbody id="tb"></tbody></table>
</main>
<script>
const DATA=__DATA__;
const VAL=__VAL__;
const $=id=>document.getElementById(id);
let cls=DATA[0].cls, spec=DATA[0].spec;
function esc(s){return String(s).replace(/[&<>]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]))}
$('valcard').innerHTML=VAL;
function tabs(){
 const classes=[...new Set(DATA.map(x=>x.cls))];
 $('ctabs').innerHTML=classes.map(c=>`<button class="${c===cls?'on':''}" data-c="${c}">${DATA.find(x=>x.cls===c).clsName}</button>`).join('');
 $('stabs').innerHTML=DATA.filter(x=>x.cls===cls).map(x=>`<button class="${x.spec===spec?'on':''}" data-s="${x.spec}">${esc(x.specName)}</button>`).join('');
 $('ctabs').onclick=e=>{const c=e.target.dataset.c;if(!c)return;cls=c;spec=DATA.find(x=>x.cls===c).spec;render()};
 $('stabs').onclick=e=>{const s=e.target.dataset.s;if(!s)return;spec=s;render()};
}
function render(){
 tabs();
 const sd=DATA.find(x=>x.cls===cls&&x.spec===spec);
 const q=$('q').value.toLowerCase(), fs=$('fskip').checked, fd=$('fdis').checked, ff=$('fflip').checked, f60=$('fno60').checked, fu=$('funs').checked;
 let n=0, html='';
 for(const r of sd.rows){
  const [lvl,spell,rank,dec,st,price,psrc,hrs,gain,use,ben,cost,cur,delta,why,kind,pet,wh,whdis,whcur,whtext]=r;
  if(q&&!spell.toLowerCase().includes(q))continue;
  if(fs&&dec!=='SKIP')continue;
  if(fd&&!(delta==='model-buys'||delta==='model-skips'))continue;
  if(ff&&st!=='flips with assumptions')continue;
  const fw=$('fwh').value;
  if(fw==='override'&&whdis!=='override')continue;
  if(fw==='cur'&&whcur!=='cur')continue;
  if(fw==='filled'&&whdis!=='filled')continue;
  if(fw==='any'&&!wh)continue;
  if(fw==='all'){ if(f60&&st==='rule R2')continue; if(fu&&dec==='UNSCORED')continue; }
  n++;
  const dis=(delta==='model-buys'||delta==='model-skips')||whdis==='override';
  const flag=st==='Wowhead'?' <span class="tag">Wowhead decides</span>':st==='flips with assumptions'?' <span class="flip">flips</span>':(st==='rule R2'?' <span class="tag">level 60 rule</span>':'');
  const curtag=cur?'<span class="tag">current: skip</span>':'';
  const kt=kind==='weapon'?'<span class="tag">low confidence</span>':'';
  html+=`<tr class="${dis?'dis':''}" title="${esc(whtext)}"><td class="n">${lvl}</td><td>${esc(spell)}${pet?'<span class="tag">pet</span>':''}${curtag}${kt}</td><td class="n">${rank}</td><td><span class="pill ${dec}">${dec}</span>${flag}</td><td>${wh?`<span class="pill ${wh==='buy'?'BUY':'SKIP'}" title="${esc(whtext)}">${wh.toUpperCase()}</span>${whdis==='override'?' <span class="flip">overrode model</span>':''}`:'<span class="mut">-</span>'}</td><td class="n">${esc(price)}<div class="mut" style="font-size:11px">${esc(psrc)}</div></td><td class="n">${hrs}</td><td class="n">${gain?'+'+gain+'%':'-'}</td><td class="n">${use}</td><td class="n">${ben}</td><td class="n">${cost}</td><td class="reason">${esc(why)}</td></tr>`;
 }
 $('tb').innerHTML=html; $('count').textContent=n+' rows';
}
['q','fskip','fdis','fflip','fno60','funs','fwh'].forEach(id=>$(id).addEventListener('input',render));
render();
</script></body></html>
"""
cnt = collections.Counter(r[18] for sd in data for r in sd['rows'] if r[18])
val = ('<b>Wowhead decides where it has a view.</b> For a spec, spell and rank that a Wowhead leveling guide covers (Priest, Mage, Druid, Shaman and Warrior), Wowhead\'s view is the decision, shown with a <i>Wowhead decides</i> tag. '
       f'It overrode the model on {cnt["override"]} ranks, filled in {cnt["filled"]} the model could not score, and agreed on {cnt["agree"]}. '
       'This includes ranks that unlock at level 60: where Wowhead trains one at 60, it is BUY here, even though the earlier rule was to hold level 60 ranks until the mount. '
       'Everything else (Hunter, Rogue, Warlock, Paladin, and spells Wowhead does not mention) is still the model\'s calculation, shown with its reasoning, and has not been checked against an expert guide.')
page = page.replace('__DATA__', json.dumps(data, separators=(',', ':'))).replace('__VAL__', json.dumps(val))
open(f'{OUT}/skip-review.html', 'w').write(page)
print('wrote', os.path.getsize(f'{OUT}/skip-review.html'), dict(summary))
