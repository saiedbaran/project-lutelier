"""Bake the existing Lutelier recipes into native Core Image RGBA float cubes."""
import sys, json, hashlib
from pathlib import Path
import numpy as np

source = Path(sys.argv[1])
sys.path.insert(0, str(source.parent))
from emulsion.engine.presets import BUILTIN
from emulsion.engine.lut import identity_grid

out = Path(__file__).resolve().parents[1] / 'Lutelier/Resources/Looks'
out.mkdir(parents=True, exist_ok=True)
manifest = []
for look in BUILTIN:
    if look.id == 'original':
        continue
    size = 33
    rgb = np.clip(look.evaluate(identity_grid(size)), 0, 1).reshape(size, size, size, 3)
    # Core Image expects red to change fastest, then green, then blue.
    rgba = np.ones((size, size, size, 4), dtype='<f4')
    rgba[..., :3] = rgb.transpose(2, 1, 0, 3)
    data = rgba.tobytes()
    assert len(data) == size ** 3 * 16 and np.isfinite(rgba).all()
    filename = look.id + '.rgba'
    (out / filename).write_bytes(data)
    manifest.append(dict(id=look.id, name=look.name, category=look.category,
        description=look.description, file=filename, dimension=size,
        fx=look.fx, sha256=hashlib.sha256(data).hexdigest()))
(out / 'presets.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
print(f'Exported {len(manifest)} native LUTs')
