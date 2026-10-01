"""Collect licensed studio-reference photographs from Wikimedia Commons.

Uses the public MediaWiki API; retains per-image provenance and attribution.
Run --discover first, review candidates, then --download selected page IDs.
"""
import argparse, json, urllib.request, urllib.parse, re, html, time, hashlib
from pathlib import Path
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
RESOURCE = ROOT / 'Lutelier/Resources/Studio'
RESEARCH = ROOT / 'studio-research'
API = 'https://commons.wikimedia.org/w/api.php'
HEADERS = {'User-Agent': 'LutelierStudioReferences/1.0 (reference-photo attribution collector; no model training)'}

def request(url):
    for attempt in range(4):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=HEADERS), timeout=30) as response:
                return response.read()
        except Exception:
            if attempt == 3: raise
            time.sleep(2 * (attempt + 1))

def api(**params):
    return json.loads(request(API + '?' + urllib.parse.urlencode({'action':'query','format':'json', **params})))

def clean(value):
    return html.unescape(re.sub('<[^>]+>', '', value)).strip()

def discover():
    RESEARCH.mkdir(exist_ok=True)
    queries = [
        '"studio portrait" -LCCN -NARA -LOC -Besarab -"cropped" filetype:bitmap',
        '"portrait" "studio" "lighting" filetype:bitmap',
        '"portrait" "studio" "model" -LCCN filetype:bitmap',
        '"portrait" "studio" "fashion" filetype:bitmap',
        '"portrait" "background" "pink" filetype:bitmap',
        '"portrait" "background" "blue" filetype:bitmap',
        '"portrait" "background" "black" "studio" filetype:bitmap',
        '"portrait" "background" "white" "studio" filetype:bitmap',
        '"portrait" "studio" "seated" -LCCN filetype:bitmap',
        '"Lies Thru a Lens" "portrait" -nude -naked -lingerie -bikini -topless filetype:bitmap',
        '"Jef Harris" "portrait" -nude -naked -lingerie -bikini -topless filetype:bitmap',
        '"FRITSCHI PHOTOGRAPHY" "portrait" -nude -naked -lingerie -bikini -topless filetype:bitmap',
        '"studio" "Rembrandt" "portrait" -painting filetype:bitmap',
        '"studio" "gel" "portrait" filetype:bitmap',
        '"studio" "model" "background" -WikiPortraits -nude -naked -lingerie -bikini -topless filetype:bitmap',
        '"Studio Harcourt" "portrait" filetype:bitmap',
        '"studio portrait photography" filetype:bitmap',
        'incategory:"Studio portrait photographs of people" -WikiPortraits -nude -naked filetype:bitmap',
    ]
    previous=json.loads((RESEARCH/'candidates.json').read_text(encoding='utf-8')) if (RESEARCH/'candidates.json').exists() else []
    found = {x['pageID']:x for x in previous}
    covered={q for x in previous for q in x['queries']}
    for query in queries:
        if query in covered: continue
        try:
            result = api(generator='search', gsrsearch=query, gsrnamespace=6, gsrlimit=50,
                prop='imageinfo', iiprop='url|extmetadata|size|sha1', iiurlwidth=330)
        except Exception as error:
            print(f'Query unavailable: {error}; preserving prior results',flush=True)
            continue
        for page in result.get('query',{}).get('pages',{}).values():
            info = page.get('imageinfo',[{}])[0]
            meta = info.get('extmetadata',{})
            def field(key): return clean(meta.get(key,{}).get('value',''))
            license_name = field('LicenseShortName').lower()
            if not (license_name.startswith('cc by') or license_name in ('cc0','public domain','pdm')): continue
            if any(x in license_name for x in ['nc','nd']): continue
            if info.get('width',0) < 400 or info.get('height',0) < 400: continue
            if not urllib.parse.urlparse(info.get('url','')).path.lower().endswith(('.jpg','.jpeg','.png')): continue
            date = field('DateTimeOriginal') or field('DateTime')
            match = re.search(r'\b(18\d{2}|19\d{2}|20\d{2})\b',date)
            if match and int(match[1]) < 1990: continue
            record = dict(pageID=page['pageid'], title=page['title'], description=field('ImageDescription'),
                author=field('Artist'), credit=field('Credit'), license=field('LicenseShortName'),
                licenseURL=field('LicenseUrl'), sourceURL=info.get('descriptionurl',''),
                originalURL=info.get('url',''), downloadURL=info.get('thumburl',info.get('url','')),
                date=date, width=info.get('width'), height=info.get('height'), originalSHA1=info.get('sha1'),
                queries=[query], attributionRequired=field('AttributionRequired'))
            if page['pageid'] in found: found[page['pageid']]['queries'].append(query)
            else: found[page['pageid']] = record
        print(f'Found {len(found)} eligible candidates after query {queries.index(query)+1}', flush=True)
        (RESEARCH/'candidates.json').write_text(json.dumps(list(found.values()),indent=2,ensure_ascii=False),encoding='utf-8')
        time.sleep(2)
    (RESEARCH/'candidates.json').write_text(json.dumps(list(found.values()),indent=2,ensure_ascii=False),encoding='utf-8')
    print('Candidate metadata saved for review',flush=True)

def download():
    RESOURCE.mkdir(parents=True,exist_ok=True)
    candidates={x['pageID']:x for x in json.loads((RESEARCH/'candidates.json').read_text(encoding='utf-8'))}
    selected=json.loads((RESEARCH/'selection.json').read_text(encoding='utf-8'))
    # Request a cached, standard thumbnail size, even for small original photos.
    # Downloading originals can hit Wikimedia's separate original-file rate limit.
    for offset in range(0,len(selected),30):
        batch=selected[offset:offset+30]
        result=api(pageids='|'.join(str(x['pageID']) for x in batch),prop='imageinfo',iiprop='url',iiurlwidth=330)
        for page in result.get('query',{}).get('pages',{}).values():
            info=page.get('imageinfo',[{}])[0]
            if info.get('thumburl'): candidates[page['pageid']]['downloadURL']=info['thumburl']
        time.sleep(2)
    manifest=[]
    for index, entry in enumerate(selected):
        record=candidates[entry['pageID']]
        extension=Path(urllib.parse.urlparse(record['downloadURL']).path).suffix.lower()
        if extension not in ('.jpg','.jpeg','.png'): extension='.jpg'
        filename=f'studio-{index+1:03d}{extension}'
        path=RESOURCE/filename
        if not path.exists(): path.write_bytes(request(record['downloadURL']))
        digest=hashlib.sha256(path.read_bytes()).hexdigest()
        manifest.append(dict(id=f'studio-{index+1:03d}',name=entry['name'],category=entry['category'],
            file=filename,brief=entry.get('brief',''),sourceTitle=record['title'],
            author=record['author'],credit=record['credit'],license=record['license'],licenseURL=record['licenseURL'],
            sourceURL=record['sourceURL'],downloadURL=record['downloadURL'],sha256=digest,
            modification='Wikimedia thumbnail, scaled by its server; bundled without additional edits',
            retrieved=datetime.now(timezone.utc).date().isoformat(),isCustom=False))
        (RESOURCE/'templates.json').write_text(json.dumps(manifest,indent=2,ensure_ascii=False),encoding='utf-8')
        if (index+1)%10==0: print(f'Downloaded {index+1}/{len(selected)}',flush=True)
        time.sleep(1)
    (RESOURCE/'templates.json').write_text(json.dumps(manifest,indent=2,ensure_ascii=False),encoding='utf-8')
    print(f'Bundled {len(manifest)} licensed photographs',flush=True)

if __name__=='__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('--discover',action='store_true'); parser.add_argument('--download',action='store_true')
    args=parser.parse_args()
    if args.discover: discover()
    if args.download: download()
