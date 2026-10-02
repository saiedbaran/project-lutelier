"""Windows-safe resource/project checks. Native XCTest still requires Xcode."""
from pathlib import Path
import json, hashlib, plistlib, re, sys
from collections import Counter
import numpy as np
from PIL import Image

root = Path(__file__).resolve().parents[1]
checks = []
def check(condition, description):
    if not condition: raise AssertionError(description)
    checks.append(description)

manifest = json.loads((root/'Lutelier/Resources/Looks/presets.json').read_text())
check(len(manifest) == 114, '114 graded LUTs packaged; Original supplied by Swift')
check(len({x['id'] for x in manifest}) == 114, 'Look identifiers are unique')
for look in manifest:
    data = (root/'Lutelier/Resources/Looks'/look['file']).read_bytes()
    table = np.frombuffer(data, dtype='<f4').reshape(-1,4)
    check(len(data) == look['dimension']**3 * 16, f"{look['id']}: Core Image byte count")
    check(hashlib.sha256(data).hexdigest() == look['sha256'], f"{look['id']}: data checksum")
    check(np.isfinite(table).all() and (table[:,:3]>=0).all() and (table[:,:3]<=1).all() and (table[:,3]==1).all(), f"{look['id']}: finite normalized RGBA")

if len(sys.argv) > 1:
    source=Path(sys.argv[1]); sys.path.insert(0,str(source.parent))
    from emulsion.engine.presets import BUILTIN
    original={look.id:look for look in BUILTIN}
    points=[(0,0,0),(1,0,0),(0,1,0),(0,0,1),(1,1,1),(0.25,0.5,0.75)]
    for look in manifest:
        size=look['dimension']; data=(root/'Lutelier/Resources/Looks'/look['file']).read_bytes()
        table=np.frombuffer(data,dtype='<f4').reshape(size,size,size,4)
        expected=original[look['id']].evaluate(np.array(points,dtype=np.float32))
        for point,color in zip(points,expected):
            r,g,b=[round(v*(size-1)) for v in point]
            check(np.allclose(table[b,g,r,:3],np.clip(color,0,1),atol=1e-6),f"{look['id']}: source parity at {point}")

# Parse the OpenStep project format, including quoted strings and trailing commas.
text=(root/'Lutelier.xcodeproj/project.pbxproj').read_text()
text=re.sub(r'//[^\n]*|/\*.*?\*/','',text,flags=re.S)
tokens=re.findall(r'"(?:\\.|[^"\\])*"|[{}()=;,]|[^\s{}()=;,]+',text)
cursor=0
def take():
    global cursor
    token=tokens[cursor]; cursor+=1; return token
def parse():
    token=take()
    if token=='{':
        value={}
        while tokens[cursor]!='}':
            key=take().strip('"'); assert take()=='='
            value[key]=parse(); assert take()==';'
        take(); return value
    if token=='(':
        value=[]
        while tokens[cursor]!=')':
            value.append(parse())
            if tokens[cursor]==',': take()
        take(); return value
    return token.strip('"')
project=parse(); check(cursor==len(tokens),'Xcode project parses as OpenStep property list')
objects=project['objects']
check(project['rootObject'] in objects,'Xcode root object resolves')
for key,value in objects.items():
    if value.get('isa')=='PBXFileReference' and value.get('sourceTree')=='SOURCE_ROOT':
        check((root/value['path']).exists(),f"Project source/resource exists: {value['path']}")
    for field in ['fileRef','buildConfigurationList','target','targetProxy','mainGroup','productReference','productRefGroup','containerPortal','remoteGlobalIDString']:
        if field in value: check(value[field] in objects,f'Project reference {field} resolves')
    for field in ['children','buildConfigurations','buildPhases','dependencies','targets','files']:
        if field in value: check(all(ref in objects for ref in value[field]),f'Project list {field} resolves')
info=plistlib.loads((root/'Lutelier/Info.plist').read_bytes())
check('NSCameraUsageDescription' in info and 'NSPhotoLibraryAddUsageDescription' in info,'Camera and Photos usage strings configured')
for path in (root/'Lutelier/Assets.xcassets').rglob('Contents.json'): json.loads(path.read_text())
icon=Image.open(root/'Lutelier/Assets.xcassets/AppIcon.appiconset/icon_1024.png')
check(icon.size==(1024,1024),'App icon is 1024 × 1024')
alpha=icon.getchannel('A').getextrema() if 'A' in icon.getbands() else (255,255)
report={'status':'passed','checks':len(checks),'looks':len(manifest),'categories':dict(Counter(x['category'] for x in manifest)), 'lut_megabytes':round(sum((root/'Lutelier/Resources/Looks'/x['file']).stat().st_size for x in manifest)/1024**2,2), 'icon_alpha_extrema':alpha,'native_build':'Not run: Windows host has no Xcode or iOS SDK','native_tests':'RenderTests.swift provided; requires Mac simulator'}
studio_directory=root/'Lutelier/Resources/Studio'
studio=json.loads((studio_directory/'templates.json').read_text(encoding='utf-8'))
check(len(studio)==100,'Studio contains exactly 100 references')
check(len({x['id'] for x in studio})==100,'Studio identifiers are unique')
check(len({x['sourceURL'] for x in studio})==100,'Studio source pages are unique')
check(len({x['sha256'] for x in studio})==100,'Studio reference bytes are distinct')
referenced={x['file'] for x in studio}
check({x.name for x in studio_directory.iterdir() if x.suffix.lower() in ['.jpg','.jpeg','.png']}==referenced,'Studio folder contains only the 100 selected photos')
for template in studio:
    path=studio_directory/template['file']
    check(path.exists(),f"{template['id']}: reference file exists")
    check(hashlib.sha256(path.read_bytes()).hexdigest()==template['sha256'],f"{template['id']}: reference checksum")
    image=Image.open(path);image.verify()
    check(bool(template['author']) and bool(template['license']) and bool(template['licenseURL']) and template['sourceURL'].startswith('https://commons.wikimedia.org/wiki/'),f"{template['id']}: photo attribution and license links")
    check(not template['isCustom'] and len(template['brief'])>30,f"{template['id']}: usable predefined photographic direction")
credits=(root/'STUDIO-CREDITS.md').read_text(encoding='utf-8')
check(all(x['sourceURL'] in credits for x in studio),'Every bundled Studio photo appears in the credits')
check(any(x.get('path')=='Lutelier/Resources/Studio' for x in objects.values()),'Xcode project includes Studio resource folder')
report.update(checks=len(checks),studio_references=len(studio),studio_categories=dict(Counter(x['category'] for x in studio)),studio_megabytes=round(sum((studio_directory/x['file']).stat().st_size for x in studio)/1024**2,2),minimum_ios='27.0',studio_native_generation='Not tested: needs supported iOS 27 Apple Intelligence device')
model=root/'Lutelier/Resources/Models/DepthAnythingV2SmallF16.mlpackage'
model_manifest=json.loads((model/'Manifest.json').read_text())
check(bool(model_manifest['itemInfoEntries']),'Core ML package manifest has model entries')
for entry in model_manifest['itemInfoEntries'].values():
    check((model/'Data'/entry['path']).exists(),'Core ML model package resource exists')
weights=model/'Data/com.apple.CoreML/weights/weight.bin'
check(weights.stat().st_size>40_000_000,'Depth model weights are bundled')
check(any(x.get('path')=='Lutelier/Resources/Models' for x in objects.values()),'Xcode includes depth model folder')
check('Apache License' in (model.parent/'LICENSE-DepthAnything.txt').read_text(),'Small model license bundled')
report.update(checks=len(checks),depth_model='DepthAnythingV2SmallF16',depth_weights_sha256=hashlib.sha256(weights.read_bytes()).hexdigest(),depth_inference='Not run: needs Core ML on Apple hardware')
(root/'validation-report.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report,indent=2))
