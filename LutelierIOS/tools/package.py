"""Package the buildable project and credits, excluding collection/QA working files."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
root=Path(__file__).resolve().parents[1]
output=root.parent/'Lutelier-iOS.zip'
with ZipFile(output,'w',ZIP_DEFLATED,compresslevel=6) as archive:
    for path in sorted(root.rglob('*')):
        if not path.is_file():continue
        if path.name == 'config.local.json':continue
        relative=path.relative_to(root)
        if any(part in {'studio-research','__pycache__','build','DerivedData','xcuserdata'} for part in relative.parts):continue
        archive.write(path,Path('LutelierIOS')/relative)
with ZipFile(output) as archive:
    assert archive.testzip() is None
    names=archive.namelist()
    assert sum('/Resources/Looks/' in x and x.endswith('.rgba') for x in names)==114
    assert sum('/Resources/Studio/' in x and Path(x).suffix in {'.jpg','.jpeg','.png'} for x in names)==100
    assert 'LutelierIOS/STUDIO-CREDITS.md' in names
    assert 'LutelierIOS/Lutelier/Sources/StudioView.swift' in names
print(f'Verified package: {output.name}, {output.stat().st_size/1048576:.1f} MB, 100 reference photos, 114 LUTs')
