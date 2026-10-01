"""Prepare a limited shortlist for visual QA, not an automatic final curation."""
import json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
research=ROOT/'studio-research'
data=json.loads((research/'candidates.json').read_text(encoding='utf-8'))
selected=[]; subjects={}
groups=[
    (lambda x: x['author']=='Studio Harcourt' and 'cropped' not in x['title'].lower(), 'Classic studio', 20,1),
    (lambda x: 'Lies Thru a Lens' in x['author'] and 'cropped' not in x['title'].lower(), 'Editorial portrait', 32,2),
    (lambda x: 'Jef Harris' in x['author'], 'Creative studio', 35,2),
    (lambda x: 'WikiPortraits Studio' in x['title'] or 'WikiPortraits studio' in x['title'], 'Modern studio', 28,1),
]
for predicate,category,limit,per_subject in groups:
    count=0
    for item in data:
        if not predicate(item):continue
        title=item['title'].removeprefix('File:')
        subject=re.sub(r'portrait at.*|Portrait Series.*|\(.*|\d.*','',title,flags=re.I).strip().lower()
        if 'Lies Thru' in item['author']: subject=re.sub(r'[- ]','',title.split('(')[0].strip()).lower()
        if subjects.get(subject,0)>=per_subject:continue
        subjects[subject]=subjects.get(subject,0)+1
        selected.append(dict(pageID=item['pageID'],name=f'Reference {len(selected)+1:03d}',category=category,brief=''))
        count+=1
        if count>=limit:break
extra=[107302056,107302057,107302058,87047278,93016582,154053639,177632285,177632287,184615937,50038442,120216014,132264371,177980648,95449727,95035521,98828506]
ids={x['pageID'] for x in data};used={x['pageID'] for x in selected}
for page in extra:
    if page in ids and page not in used:
        selected.append(dict(pageID=page,name=f'Reference {len(selected)+1:03d}',category='Portrait study',brief=''))
(research/'selection.json').write_text(json.dumps(selected,indent=2),encoding='utf-8')
print(f'Shortlisted {len(selected)} references for visual review')
