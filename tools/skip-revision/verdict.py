"""What a Wowhead guide says about one rank of one spell for one spec. Shared by report.py and ../build-skip-revisions.py."""

def wowhead_view(WH, FAMLV, cls, spec, fid, rank, level, is_first):
    """Returns (view, quote, reason): view is 'buy', 'skip' or None (the guides say nothing usable);
    quote is the guide text; reason is { kind=..., n=... } for a skip."""
    rule = (WH.get(f'{cls}|{spec}') or {}).get(str(fid))
    if not rule or is_first: return None, '', None
    q = rule['quote'] + ' (' + rule['source'] + ')'
    k = rule['kind']
    if k == 'all': return 'buy', q, None
    if k in ('only1', 'skipall'):
        if rank <= 1: return 'buy', q, None
        return 'skip', q, {'kind': 'guideSkipEntirely' if k == 'skipall' else 'guideFirstRankOnly'}
    if k == 'upto':
        if rank <= rule['n']: return 'buy', q, None
        return 'skip', q, {'kind': 'guideUpToRank', 'n': rule['n']}
    lv = rule['levels']
    forever = FAMLV.get((cls, fid), set())
    if sum(1 for x in lv if x in forever) < 0.7 * len(lv): return None, '', None   # the guide's levels do not line up with Forever's ranks
    if level in lv: return 'buy', q, None
    if level < min(lv): return None, '', None                                      # guides often leave out the first rank
    return 'skip', q + f' Level {level} is not in that list.', {'kind': 'guideNotTrained'}
