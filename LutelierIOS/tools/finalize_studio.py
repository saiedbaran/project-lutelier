"""Apply the visually reviewed selection and write attributable reference briefs."""
from pathlib import Path
from collections import Counter
import json,re

root=Path(__file__).resolve().parents[1]
directory=root/'Lutelier/Resources/Studio'
manifest=json.loads((directory/'templates.json').read_text(encoding='utf-8'))
assert len(manifest)==129, 'Run this once on the reviewed 129-photo shortlist'
rejected={21,24,29,30,34,38,39,40,41,43,44,47,48,49,72,95,98,108,110,86,93,96,99,101,106,107,113,123,127}
assert len(rejected)==29
# Visual descriptions are deliberately broad. On-device analysis refines them.
# Format: visible light / visible background / visible body pose or framing.
notes={
1:'sculpted soft side light / charcoal backdrop / seated, shoulders angled, direct gaze',
2:'bright directional light / dark backdrop / close-up, head slightly turned, direct gaze',
3:'soft directional light / grey backdrop / head tilted, close-up',
4:'sculpted key light / dark gradient / leaned forward, shoulders angled',
5:'high-contrast key light / black backdrop / head turned, shoulders angled',
6:'directional key and background glow / dark-to-white gradient / seated, slightly leaned forward',
7:'soft side light / charcoal gradient / three-quarter head turn, over-shoulder close-up',
8:'soft shaped light / grey gradient / head tilted, direct gaze',
9:'soft key with rim separation / dark gradient / seated, shoulder turned toward camera',
10:'soft directional light / grey vignette / three-quarter head angle',
11:'directional studio light / dark interior with a standing lamp / seated, hands resting together',
12:'soft bright side light / dark gradient / shoulders angled, direct gaze',
13:'sculpted side light / dark gradient / seated, forearms resting together',
14:'soft key and background halo / dark-to-white gradient / close head-and-shoulders portrait',
15:'dramatic low-key light / black backdrop / side-facing head angle, hat casting a shadow',
16:'low-key front-side light / dark gradient / leaned forward, chin above clasped hands',
17:'soft frontal key / dark background / face resting between both hands',
18:'soft flattering key / textured grey background / relaxed seated portrait',
19:'sculpted monochrome key / grey gradient / head raised, gaze upward to the side',
20:'soft natural-looking side light / pale interior / hand near lips, over-shoulder close-up',
22:'bright diffuse light / white backdrop / hand near shoulder, head tilted, close-up',
23:'directional close-up light / muted blurred background / face leaning toward one hand, direct gaze',
25:'diffuse light / white backdrop / three-quarter shoulders, hand on opposite shoulder',
26:'warm soft side light / dark blue-black background / hand close to cheek, head turned',
27:'very bright diffuse light / white background / head lowered and turned, close-up',
28:'yellow-toned high-contrast light / muted dark background / leaned-forward close-up',
31:'bright diffuse light / white backdrop / fingertips near the neck, direct gaze',
32:'high-key diffuse light / white seamless / standing with both hands behind the head',
33:'low-key soft light / dark background / close-up, face resting against a hand',
35:'soft monochrome light / blurred indoor backdrop / seated, chin resting on one hand',
36:'warm side light / warm textured background / seated, one hand lifted to the head',
37:'soft frontal light / dark backdrop with deep blue fabric / tight frontal portrait',
42:'bright diffuse light / white studio backdrop / leaning forward, upper-body portrait',
45:'warm vintage-toned light / decorated studio interior / seated, arm raised, gaze to the side',
46:'soft window-like light / blurred pale interior / seated, head turned back toward camera',
50:'soft directional light / light grey backdrop / three-quarter head turn, gaze to the side',
51:'warm low-key light / black background / shoulder turned, hand holding upper arm',
52:'deep blue gel lighting / dark blue backdrop / close frontal portrait with ornamental makeup',
53:'cyan gel lighting / cyan-to-black backdrop / turned head-and-shoulders portrait with ornamental makeup',
54:'blue and magenta accent lights / saturated blue backdrop / three-quarter portrait with colourful makeup',
55:'magenta and cyan gels / black backdrop / turned close-up with sculptural headpiece',
56:'magenta and blue gels / black backdrop / close portrait with sculptural headpiece',
57:'cyan and red accent lights / black background / close frontal portrait with sculptural headpiece',
58:'blue key and red rim light / red-to-black gradient / head turned upward',
59:'blue overhead-side light / black gradient / profile portrait, head slightly raised',
60:'hard directional key / black backdrop / head raised, dramatic shadowed profile',
61:'blue key and warm rim / blue-to-black gradient / three-quarter portrait with decorative makeup',
62:'cool cyan and warm accents / black backdrop / close frontal portrait with round decorative makeup',
63:'blue and yellow gel split / blue-yellow backdrop / one arm lifted above head, upper-body portrait',
64:'yellow key with cool edge light / muted gradient / close profile with sculptural headpiece',
65:'warm yellow key and cool accents / textured muted background / three-quarter upper-body portrait',
66:'cyan and magenta gels / textured purple background / both hands framing the neck, direct gaze',
67:'magenta and green split gels / dark backdrop / frontal upper-body portrait',
68:'cool low-key light / black backdrop / three-quarter face close-up',
69:'blue background glow and warm rim / black-to-blue gradient / strongly side-facing profile',
70:'cool sculpted light / black backdrop / head-and-shoulders portrait with decorative round makeup',
71:'warm amber key / black background / turned face, dramatic close-up',
73:'magenta and blue gels / purple background / one arm lifted, sideways head turn',
74:'warm yellow key / black backdrop / three-quarter face turned to side',
75:'red and blue split lights / red-blue backdrop / tight frontal portrait with textured makeup',
76:'blue and yellow accents / dark muted gradient / tilted close portrait with colourful makeup',
77:'cool blue key and orange rim / orange gradient / face in profile, gaze upward',
78:'soft cool green-tinted light / muted green background / profile head-and-shoulders portrait',
79:'bright cool key / muted dark background / shoulders angled, direct gaze',
80:'cyan key and magenta rim / black backdrop / three-quarter profile with a sculptural headpiece',
81:'blue and purple gels / vivid violet backdrop / three-quarter head angle with sculptural headpiece',
82:'magenta and violet gels / violet backdrop / sideways upper-body portrait with sculptural headpiece',
83:'red and amber directional lights / dark gradient / close portrait, head tilted upward',
84:'red key and cool edge / blue-black gradient / side-facing upper-body portrait',
85:'blue key and red rim / red-to-black gradient / strongly turned profile, head raised',
87:'soft key with gentle contrast / dark blue seamless / standing, hands behind back, full torso',
88:'soft diffuse light / textured tan backdrop / standing three-quarter torso, direct gaze',
89:'soft frontal-side key / dark blue backdrop / upright head-and-shoulders portrait',
90:'soft key / dark blue backdrop / seated, head tilted, hands together on lap',
91:'soft studio key / charcoal textured backdrop / standing, arms folded, three-quarter torso',
92:'soft warm studio key / brown textured backdrop / standing with folded arms',
94:'soft frontal-side light / warm grey textured background / seated, head tilted, upper-body portrait',
97:'soft front-side key / dark blue background / standing or seated with hands together in front',
100:'soft broad key / charcoal textured backdrop / upright head-and-shoulders portrait',
102:'warm sculpted light / charcoal textured backdrop / three-quarter shoulder turn',
103:'soft shaped key / dark blue seamless / three-quarter torso with a slight head tilt',
104:'soft broad key / dark blue seamless / upright upper-body portrait with gaze to the side',
105:'soft even studio key / grey textured background / standing three-quarter torso',
109:'soft side key / dark blue backdrop / seated with one hand resting on a chair',
111:'soft directional light / dark blue seamless / standing with one hand near the shoulder',
112:'soft studio key / dark blue background / standing full-body pose, holding jacket open',
114:'bright diffuse key / light grey background / seated, hands holding a blue umbrella',
115:'bright diffuse key / light grey seamless / standing three-quarter torso, arms folded',
116:'bright diffuse key / pale grey seamless / seated sideways, arms folded, direct smile',
117:'soft even light / grey textured backdrop / tight head-and-shoulders portrait',
118:'low-key shaped light / black background / frontal portrait with hands together near chin',
119:'low-key soft side light / black backdrop / turned close-up with gaze to the side',
120:'soft bright light / pale blue background / hands near neck and shoulder, three-quarter torso',
121:'bright soft key / decorative interior backdrop / standing three-quarter torso, one hand on hip',
122:'soft even key / warm textured backdrop / seated or standing upright torso, direct gaze',
124:'soft monochrome key / grey textured background / relaxed frontal upper-body portrait',
125:'warm diffuse side light / pale cream background / head tilted, one hand near face, upper-body crop',
126:'soft directional key / blue seamless backdrop / smiling profile, face turned to side',
128:'bright even studio light / white background / upright shoulders, arms folded, direct gaze',
129:'soft monochrome interior light / softly blurred bookshelves / seated upright upper-body portrait',
}
assert set(notes)==set(range(1,130))-rejected
selected=[]; counters=Counter(); review=[]
for old in manifest:
    number=int(old['id'].split('-')[-1])
    if number in rejected:
        path=(directory/old['file']).resolve()
        assert path.parent==directory.resolve() and re.fullmatch(r'studio-\d{3}\.(jpg|jpeg|png)',path.name)
        path.unlink()
        review.append({'originalID':old['id'],'selected':False,'sourceURL':old['sourceURL']})
        continue
    category=('Classic noir' if number<=19 else 'Editorial' if number<=51 else 'Gel & colour' if number<=85 else 'Modern studio' if number<=113 else 'Portrait study')
    counters[category]+=1
    light,background,pose=notes[number].split(' / ')
    old['name']=f'{category} {counters[category]:02d}'
    old['category']=category
    old['brief']=f'Lighting: {light}. Background: {background}. Pose and framing: {pose}. Use a finished photographic treatment; keep the source person recognizable.'
    if not old['licenseURL'] and old['license']=='Public domain': old['licenseURL']=old['sourceURL']
    old['id']=f'studio-{len(selected)+1:03d}'
    selected.append(old)
    review.append({'originalID':f'studio-{number:03d}','finalID':old['id'],'selected':True,'sourceURL':old['sourceURL']})
assert len(selected)==100 and len({x['sha256'] for x in selected})==100
(directory/'templates.json').write_text(json.dumps(selected,indent=2,ensure_ascii=False),encoding='utf-8')
(root/'studio-research/visual-selection.json').write_text(json.dumps(review,indent=2),encoding='utf-8')
credits=['# Studio reference photo credits','',
    'The following 100 Wikimedia Commons photographs are bundled as aesthetic references. Each remains under its own license. The app displays the same creator and license information beside its reference. No endorsement by photographers or depicted people is implied. References are not training data.','',
    'Bundled files are server-generated thumbnails; no additional edits were made to the reference files. Selection names and photographic briefs are original Lutelier metadata. For applicable licenses, retain attribution and license links, and share adapted copies under the same license when required.','']
for item in selected:
    credits += [f"## {item['id']} — {item['name']}",'',f"- Original: [{item['sourceTitle']}]({item['sourceURL']})",f"- Creator: {item['author']}",f"- License: [{item['license']}]({item['licenseURL']})",f"- Bundled file: `Lutelier/Resources/Studio/{item['file']}`",f"- Changes: {item['modification']}",f"- Retrieved: {item['retrieved']}",'']
(root/'STUDIO-CREDITS.md').write_text('\n'.join(credits),encoding='utf-8')
# Remove the obsolete fourth QA page. Remaining pages are regenerated from the final manifest.
old_sheet=root/'studio-research/contact-4.jpg'
if old_sheet.exists():old_sheet.unlink()
print(json.dumps({'selected':len(selected),'categories':dict(counters)},indent=2))
