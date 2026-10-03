#!/usr/bin/env python3
"""Prepare pinned Depth Anything 3 and optional tiled Depth Pro Core ML models.

Run with Python 3.10+ and coremltools 9 installed. Xcode is required.
    python prepare_depth_models.py --work-dir /path/to/model-work [--depth-pro]
Depth Pro preserves the conversion's pruned/quantized learned weights. Its
full-image encoder returns 96px, 96px, and 192px feature grids; the decoder
runs 32px/32px/64px crops with a four-latent-pixel halo and stitches 24px
interiors. Normalize only after stitching. See DEPTH-REFINEMENT.md.
"""
from pathlib import Path
from copy import deepcopy
import argparse
import hashlib
import subprocess
import coremltools as ct
from coremltools.proto import FeatureTypes_pb2

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--work-dir', type=Path, required=True)
parser.add_argument('--depth-pro', action='store_true')
args = parser.parse_args()
base = args.work_dir.resolve()
base.mkdir(parents=True, exist_ok=True)
destination = Path(__file__).resolve().parents[1] / 'Lutelier/Resources/Models'
destination.mkdir(parents=True, exist_ok=True)

def download_package(repo, revision, name, weight_hash):
    package = base / (name + '.mlpackage')
    for relative in ['Manifest.json', 'Data/com.apple.CoreML/model.mlmodel', 'Data/com.apple.CoreML/weights/weight.bin']:
        target = package / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists():
            subprocess.run(['curl', '-fL', '--retry', '3',
                f'https://huggingface.co/{repo}/resolve/{revision}/{package.name}/{relative}', '-o', str(target)], check=True)
    weights = package / 'Data/com.apple.CoreML/weights/weight.bin'
    with weights.open('rb') as stream:
        digest = hashlib.sha256()
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    if digest.hexdigest() != weight_hash:
        raise ValueError(f'Weight checksum mismatch: {weights}')
    return package

v3 = download_package('mlboydaisuke/Depth-Anything-3-Small-CoreML',
    '768d44df07d8d97f1cb6c1e231cfcd7928c3053e', 'DepthAnythingV3_small_504',
    'a4c37eb95467b3e099af1ac34b73d15f5028e5522687e0682d6f7f93d98b7921')
subprocess.run(['xcrun', 'coremlcompiler', 'compile', str(v3), str(destination)], check=True)
if not args.depth_pro:
    raise SystemExit(0)
p = download_package('KeighBee/coreml-DepthPro',
    '59007df396f15fee4ac1d40e8958ef679b13d462', 'DepthProNormalizedInverseDepthPruned10QuantizedLinear',
    'a3623851f51cb4c74098586509eafe46e0a016b6b56c034e5207bbaf7703494d')
s=ct.utils.load_spec(str(p)); block=next(iter(s.mlProgram.functions['main'].block_specializations.values()))
ops=list(block.operations); producers={v.name:o for o in ops for v in o.outputs}
boundaries=['input_875_cast_fp16','input_883_cast_fp16','input_957_cast_fp16']
def extract(outputs,inputs,name,tile=False):
 spec=deepcopy(s); func=spec.mlProgram.functions['main']; b=next(iter(func.block_specializations.values()))
 needed=set(); seen=set(inputs)
 def visit(n):
  if n in seen:return
  seen.add(n)
  if n not in producers:return
  o=producers[n]; needed.add(id(o))
  for arg in o.inputs.values():
   for a in arg.arguments:
    if a.name:visit(a.name)
 for n in outputs:visit(n)
 del b.operations[:]; b.operations.extend(o for o in ops if id(o) in needed)
 del b.outputs[:]; b.outputs.extend(outputs)
 if inputs:
  del func.inputs[:]; del spec.description.input[:]
  for n in inputs:
   v=next(v for v in producers[n].outputs if v.name==n)
   func.inputs.add().CopyFrom(v)
   f=spec.description.input.add();f.name=n; f.type.multiArrayType.shape.extend(d.constant.size for d in v.type.tensorType.dimensions);f.type.multiArrayType.dataType=FeatureTypes_pb2.ArrayFeatureType.FLOAT16
 del spec.description.output[:]
 for n in outputs:
  v=next(v for v in producers[n].outputs if v.name==n)
  f=spec.description.output.add();f.name=n;f.type.multiArrayType.shape.extend(d.constant.size for d in v.type.tensorType.dimensions);f.type.multiArrayType.dataType=FeatureTypes_pb2.ArrayFeatureType.FLOAT16
 if tile:
  # All decoder spatial sizes are proportional to the 96px latent grid.
  for v in func.inputs:
   for d in v.type.tensorType.dimensions[-2:]:d.constant.size//=3
  for f in list(spec.description.input)+list(spec.description.output):
   sh=f.type.multiArrayType.shape;sh[-2]//=3;sh[-1]//=3
  for o in b.operations:
   if o.type not in ['const','constexpr_sparse_blockwise_shift_scale','constexpr_sparse_to_dense']:
    for v in o.outputs:
     dims=v.type.tensorType.dimensions
     if len(dims)==4:
      dims[-2].constant.size//=3;dims[-1].constant.size//=3
   if o.type=='const' and any(v.name.endswith('output_shape_0') for v in o.outputs):
    vals=o.attributes['val'].immediateValue.tensor.ints.values
    vals[-2]//=3;vals[-1]//=3
 spec.description.metadata.shortDescription='Depth Pro tiled research inference; original learned weights, bounded decoder tiles.'
 dest=base/(name+'.mlpackage')
 ct.models.utils.save_spec(spec,str(dest),weights_dir=str(p/'Data/com.apple.CoreML/weights'))
 print('Saved',name,len(b.operations),flush=True)
extract(boundaries, [], 'DepthProEncoder')
extract(['canonical_inverse_depth_cast_fp16'], boundaries, 'DepthProDecoderTile', True)
# Reserialization retains only decoder weights, reducing its package to about 9 MB.
from coremltools.converters.mil.frontend.milproto import load
q = base / 'DepthProDecoderTile.mlpackage'
decoder_spec = ct.utils.load_spec(str(q))
program = load.load(decoder_spec, decoder_spec.specificationVersion, str(q / 'Data/com.apple.CoreML/weights'))
compact = ct.convert(program, convert_to='mlprogram', minimum_deployment_target=ct.target.iOS18,
                     pass_pipeline=ct.PassPipeline.EMPTY, skip_model_load=True)
compact.save(str(base / 'DepthProDecoder.mlpackage'))
for name in ['DepthProEncoder', 'DepthProDecoder']:
    subprocess.run(['xcrun', 'coremlcompiler', 'compile', str(base / (name + '.mlpackage')), str(destination)], check=True)

