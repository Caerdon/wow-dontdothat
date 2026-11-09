"""Reads what the Wowhead leveling guides say about each spell rank, per spec, into wowhead_rules.json.
Two kinds of statement: "you can train this at levels ..." lists (parsed from the guide text) and a few curated
sentences quoted from the guides ("Only Rank 1 of ...", "Up to Rank 4 of ..."). See README.md."""
import re,json,collections,os,argparse
_ap=argparse.ArgumentParser(); _ap.add_argument('--work',required=True); AN=_ap.parse_args().work
rules=json.load(open(f'{AN}/rules.json'))
GUIDE={'9169':('MAGE','FROST'),'9170':('MAGE','ARCANE'),'9171':('MAGE','FIRE'),'9086':('PRIEST','HOLY'),'9092':('PRIEST','DISC'),'9093':('PRIEST','SHADOW'),
 '9214':('DRUID','FERAL'),'9216':('DRUID','BAL'),'9215':('DRUID','RESTO'),'9123':('SHAMAN','ENH'),'9121':('SHAMAN','ELEM'),'9122':('SHAMAN','RESTO'),
 '9150':('WARRIOR','ARMS'),'9168':('WARRIOR','FURY'),'9172':('WARRIOR','PROT')}
names={c:{f['name']:int(i) for i,f in v['families'].items()} for c,v in rules.items()}
txt=open(f'{AN}/wowhead_guides.txt',encoding='utf8').read()
secs=re.split(r'^===== (\d+)\.html\n',txt,flags=re.M)
out=collections.defaultdict(dict); unmatched=collections.Counter()
for i in range(1,len(secs),2):
    gid,body=secs[i],secs[i+1]
    if gid not in GUIDE: continue
    cls,spec=GUIDE[gid]
    for line in body.split('\n'):
        m=re.search(r'following levels:?\s*([\d,\sand]+)',line)
        if not m: continue
        lv=[int(x) for x in re.findall(r'\d+',m.group(1))]
        clean=re.sub(r'^-\s*','',line).strip()
        name=None
        for nme in sorted(names[cls],key=len,reverse=True):
            if clean.startswith(nme) and re.match(r'(?:\s*:|\s+-\s|\s+You can|\s+\()',clean[len(nme):]): name=nme; break
        if name is None and gid in ('9215','9216') and re.match(r'^-?\s*You can train this at the following levels',clean): name='Rejuvenation'  # spell link did not render in the guide text
        if name is None:
            nm=re.match(r'^([^:]{2,45}?)\s*(?::|\s-\s)',clean); name=nm.group(1).strip() if nm else None
        if name in names[cls]:
            out[(cls,spec)][names[cls][name]]=dict(kind='levels',levels=lv,source=f'Wowhead guide {gid}',quote=f'{name}: you can train this at levels {", ".join(map(str,lv))}.')
        else: unmatched[(cls,name)]+=1
# curated text rules (quoted from the guides)
def rule(cls,specs,spell,kind,n,quote,src):
    for s in specs:
        fid=names[cls].get(spell)
        if fid: out[(cls,s)][fid]=dict(kind=kind,n=n,source=src,quote=quote)
        else: unmatched[(cls,spell)]+=1
W=['ARMS','FURY','PROT']
q1='"Only Rank 1 of Overpower, Revenge, Thunder Clap, Cleave, Mocking Blow, Demoralizing Shout, Intercept, Shield Bash, and Pummel"'
for sp in ['Overpower','Revenge','Thunder Clap','Cleave','Mocking Blow','Demoralizing Shout','Intercept','Shield Bash','Pummel']:
    rule('WARRIOR',W,sp,'only1',1,q1,'Wowhead guides 9150/9168/9172')
q2='"Up to Rank 4 of Heroic Strike and Rend"'
for sp in ['Heroic Strike','Rend']: rule('WARRIOR',W,sp,'upto',4,q2,'Wowhead guides 9150/9168/9172')
rule('WARRIOR',['ARMS'],'Mortal Strike','all',0,'"Every Rank of Battle Shout and Mortal Strike"','Wowhead guide 9150')
rule('WARRIOR',['FURY'],'Bloodthirst','all',0,'"Every Rank of Battle Shout and Bloodthirst"','Wowhead guide 9168')
rule('WARRIOR',W,'Battle Shout','all',0,'"Every Rank of Battle Shout"','Wowhead guides 9150/9168/9172')
rule('WARRIOR',W,'Slam','skipall',1,'"Slam can be skipped entirely as it is not used in the leveling process"','Wowhead guides 9150/9168/9172')
S=['ENH','ELEM','RESTO']
for sp in ['Lightning Shield','Rockbiter Weapon']: rule('SHAMAN',S,sp,'all',0,'"Always buy new ranks of Lightning Shield and Rockbiter Weapon... no matter what your spec is"','Wowhead guides 9121/9122/9123')
rule('SHAMAN',S,'Frost Shock','only1',1,'"You will usually only want the first rank of Frost Shock, for its slowing effect, but consider getting the next ranks if you plan on doing any PvP"','Wowhead guides 9121/9122/9123')
for sp in ['Lightning Bolt','Chain Lightning']: rule('SHAMAN',['ENH','ELEM'],sp,'all',0,'"You need to always buy the new ranks of your damage spells"','Wowhead guides 9121/9123')
M=['FROST','ARCANE','FIRE']
for sp in ['Arcane Intellect','Frost Armor','Ice Armor','Ice Barrier']: rule('MAGE',M,sp,'all',0,'"Always buy new ranks of your buffs: Arcane Intellect, Frost Armor, Ice Armor, and Ice Barrier"','Wowhead guide 9065')
for sp in ['Frost Nova','Blink','Evocation']: rule('MAGE',M,sp,'only1',1,'"Buy only the first ranks of your utility spells... Frost Nova, Blink, Evocation"','Wowhead guide 9065')
json.dump({f'{c}|{s}':{str(f):v for f,v in d.items()} for (c,s),d in out.items()},open(f'{AN}/wowhead_rules.json','w'))
print({f'{c}|{s}':len(d) for (c,s),d in out.items()})
print('unmatched',sorted((str(k),v) for k,v in unmatched.items())[:60])
