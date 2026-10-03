# On-device depth and portrait edges

All inference runs inside Lutelier on the iPhone. There is no companion computer,
network depth endpoint, or external model server. White means near; the normalized
maps used by the editor are not measurements in metres.

## Model choices

| Engine | Integration | Measured inference on iPhone 16 Pro |
| --- | --- | --- |
| Depth Anything V2 Small F16 | Apple's Core ML conversion, about 50 MB | 7.64 s |
| Depth Anything 3 Small | Daisuke Majima's Core ML conversion, about 69 MB | 9.74 s |
| Depth Pro | Separate full-image encoder and tiled decoder, about 754 MB | 165.59 s |

These are single-photo measurements including model loading and normalization,
not a general quality or speed benchmark. Depth Pro should be presented as an
approximately three-minute research option. All three passed actual inference,
finite/non-flat depth, foreground/background alignment, and blur-render checks
on the connected iPhone 16 Pro running iOS 27.2. The final suite passed 21 tests.

Depth Anything 3 outputs both `depth` and `confidence`. Select `depth` by name,
convert positive distance to inverse depth, then normalize. The scalar and tensor
paths preserve image orientation. Red-channel scalar maps are displayed as gray,
including older saved maps. `.Rf` readback disables color conversion; passing an
unsupported DeviceGray output space previously produced zeros and a false flat-map
error. Core ML schedules V2/V3 with `.all`; Neural Engine-only execution is not promised.

## Depth Pro implementation

The original community normalized-inverse-depth conversion retains Apple's learned
weights with 10% pruning and linear quantization. Its full decoder created a
600 MB FP16 activation (about 1.2 GB as FP32), which failed on this phone.

The adapted encoder preserves the full-image context and returns feature grids
at 96, 96, and 192 pixels, each with 256 channels. The original convolution decoder
runs sequentially on sixteen 32/32/64-pixel feature crops. A four-latent-pixel halo
is discarded; 24-pixel interiors are stitched into a 1536px map. Normalization
happens after stitching. Learned weights and global encoder inputs are retained.
The encoder is released before the roughly 9 MB decoder is loaded. Core ML uses
CPU/GPU execution with low-precision GPU accumulation. App-level thermal gates
are removed; Detail tiles remains available. System thermal management still applies.

Two offset decoder tiles produced identical shared interior values on Mac
(maximum and mean absolute error 0). Device runs completed in 171.01, 164.17, and
165.59 seconds. The final map was visually inspected for orientation and seams.
The studio portrait's mean normalized depth was 0.875 versus 0.254 for its backdrop.
This is operational validation on a reference image, not a claim of universal accuracy.

An earlier trial hit a compiler disk-space error. Abandoned app-owned compilation
caches and old temporary model copies were removed once during development; no
photos or edits were removed. This cleanup is not part of the production runtime.
The original monolithic conversion remains outside the app in the development workspace.

Depth Pro is included for the user's personal research experiment. The original
model-weight terms are bundled in `LICENSE-DepthPro.txt`; a conversion repository's
code-license label does not replace those terms.

## Portrait and hair coverage

Apple portrait effects and semantic hair mattes are separate coverage images,
not scene-depth engines. Read them from compatible captures or JPEG/HEIF auxiliary
data. Imports request `.current` encoding to avoid unnecessary transcoding.

- Capture requests portrait delivery when supported and depth capture is enabled.
- Hair delivery follows `availableSemanticSegmentationMatteTypes`, independently
  of depth availability. RAW capture disables these incompatible mattes.
- The default camera on the tested iPhone reported depth, portrait, and hair support.
  A capture request still requires a suitable detected subject to produce a matte.
- `Find portrait mask` runs Apple's accurate Vision person segmentation independently
  of the selected depth model, retaining existing depth. This passed in 0.31 seconds.
- Captured portrait coverage takes priority over Vision. Available hair coverage is
  combined with it. A person mask is never relabeled as an Apple hair matte.
- Missing hair is explained in the UI. It cannot be recovered from a plain photo
  through the capture-only Apple hair-matte API.

`Preserve portrait edges` attenuates blur with coverage. Disable it when the intended
focus plane should blur the person. Fractional coverage does not recover true hair
depth or fully remove foreground color bleeding. Depth, portrait, hair, and recipes
are saved locally. Center-cropped captures crop oriented mattes with the photograph.

## Editor and refinement

Depth sections use a full-row disclosure button. Bokeh shapes use 44-point direct
selection buttons, available before analysis. The UI explains when analysis or
nonzero Near/Far blur is needed to see an effect. Inspect Photo, Depth, Portrait,
and Hair when available. Under Refine an area, enable selection and draw a box.
Closing refinement or leaving Depth restores normal photo interaction.

- **Context**: one inference over the selection with 20% surrounding context.
- **Detail tiles (experimental)**: one context pass and four overlapping crops,
  each 68% of the context region's width/height. Robust positive scale/offset fitting
  aligns each crop with the context anchor; feathered weighted accumulation reduces
  disagreement and preserves the original map outside the selection.

The regional working grid is capped at 2048px without upscaling beyond source
resolution. Alignment uses 80% residual trimming, scale bounds 0.05–20, correlation
at least 0.35, and normalized RMSE at most 0.12. These are uncalibrated heuristics,
not learned confidence or the published PatchFusion/PatchRefiner architecture.
No accepted detail tiles means no saved change. Thermal checks prevent starting
expensive refinement when hot. Selecting Depth Pro multiplies its inference time
by the number of passes. Context is the faster default.

Optical controls support Soft, Disc, Ring, Anamorphic, and Polygon apertures;
near/far blur, focus plane, oval ratio, blade count, rotation, cat-eye clipping,
shaped highlights, highlight glow, and highlight sensitivity. The renderer uses
192 normalized aperture samples. Relative disparity now controls the blur radius
rather than crossfading a sharp image with a fixed-radius blurred copy.

Background samples exclude the protected subject and nearer depth regions before
colour integration. A small donor-only matte inset excludes mixed silhouette pixels
without expanding the visible sharp subject. Foreground blur integrates source
footprints and their coverage beyond the original silhouette; exposed edge pixels
use local background estimates. Portrait coverage is applied independently from
circle-of-confusion radius. All processing remains local.

This addresses the old whole-image blur's foreground colour leakage. It is an
approximation: hidden background cannot be recovered exactly from a single image,
coarse depth/mattes can still produce artifacts, and relative depth is not calibrated
focal distance. Inspect hair, glass, strong lights, and occlusion edges. The Bloom
control currently adds aperture-weighted highlight glow, not an additional full-frame
Gaussian blur that could reintroduce foreground leakage.

Research reviewed for this change:
- [Dr.Bokeh, CVPR 2024](https://shengcn.github.io/DrBokeh/): occlusion-aware layered
  rendering. This app adopts the visibility/coverage principle, not its full pipeline.
- [Bokehlicious, ICCV 2025](https://github.com/timseizinger/bokehlicious): a separate
  learned controllable-bokeh approach with public research checkpoints.
- [NTIRE 2026 controllable bokeh challenge](https://arxiv.org/abs/2605.05510): recent
  learned alternatives. No additional model weights were bundled for this change;
  the demonstrated whole-image colour leakage is a rendering bug independent of
  the existing depth estimator.

Photo clipping follows the visible image bounds, with a 28-point continuous corner
curve in normal, expanded, and comparison views, including when zoomed. This uses
public iOS continuous-corner rendering; iOS does not expose one universal system
corner radius for all surfaces. Editing, import/export, comparison, and camera icon
groups use shared Liquid Glass islands with separate pressed/selected overlays.

## Reproducing model resources

Use Python 3.10+ with coremltools 9 and Xcode:

```sh
python LutelierIOS/tools/prepare_depth_models.py --work-dir /path/to/model-work --depth-pro
```

Omit `--depth-pro` to prepare only Depth Anything 3. Downloads are pinned to source
revisions and weight SHA-256 hashes. Compiled model directories are excluded from
Git; licenses and attribution notices are bundled. V2's original package remains
bundled. The app shows only models whose required resources are present.

- [Apple Core ML model catalogue](https://developer.apple.com/machine-learning/models/)
- [Depth Anything 3 upstream](https://github.com/ByteDance-Seed/Depth-Anything-3)
- [Depth Anything 3 Core ML conversion](https://huggingface.co/mlboydaisuke/Depth-Anything-3-Small-CoreML)
- [Apple Depth Pro](https://github.com/apple/ml-depth-pro)
- [Depth Pro source conversion](https://huggingface.co/KeighBee/coreml-DepthPro)
- [Original Depth Pro weight license](https://huggingface.co/apple/DepthPro/blob/main/LICENSE)
- [Apple semantic matte capture](https://developer.apple.com/videos/play/wwdc2019/260/)
- [Apple portrait matte configuration](https://developer.apple.com/documentation/avfoundation/configuring-camera-capture-to-collect-a-portrait-effects-matte)


## Editor and camera interaction update

The Depth inspector uses Setup, Blur, Lens, and Refine pages. Analysis and detail
refinement share a cancellation token checked between inference passes/tiles and
before committing results. Cancellation preserves the previous depth and mattes;
an already running Core ML pass must finish first. Aperture blades are an integer
(3–9), with legacy fractional recipes rounded on decode. Sliders snap to zero or
their defaults and provide selection feedback.

Native UITabBar supplies the system glass selection lens. Action islands use
interactive SwiftUI Liquid Glass. Photo-coloured blurred illumination follows
the visible photo bounds and device tilt, with Reduce Motion respected.

Camera controls are arranged in a compact grid and focused setting drawers:
flash, Live Photo, aspect, timer, exposure, styles, depth, low-light shutter
presets, format, aperture, focus, shutter/ISO, white balance, histogram and grid.
Live Photo captures retain their motion pair and can export the original pair.
Variable aperture uses iOS 27 AVFoundation capability checks and is unavailable
on the tested iPhone 16 Pro's fixed-aperture cameras. Low light uses public manual
exposure controls, not Apple's private Night-mode processing. Styles are Lutelier
recipes applied after capture.

References:
- https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views
- https://developer.apple.com/videos/play/wwdc2025/323/
- https://support.apple.com/en-ca/guide/iphone/ipht182e41vsz41/27/ios/27
- https://www.apple.com/newsroom/2026/09/final-cut-camera-now-supports-variable-aperture-on-iphone-18-pro/
