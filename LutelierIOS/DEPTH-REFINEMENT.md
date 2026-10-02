# On-device depth and portrait edges

All depth processing runs inside Lutelier on the iPhone. There is no computer companion, network depth endpoint or external model server.

## Implemented pipeline

1. Retain the saved refined depth map when reopening a photograph. Otherwise use captured/embedded disparity when available, or estimate relative scene depth with the bundled Apple Core ML conversion of **Depth Anything V2 Small F16** (~50 MB). White means near; these normalized values are not metres. Core ML chooses available compute units.
2. Read Apple's portrait-effects and hair semantic mattes from supported processed captures or imported JPEG/HEIF auxiliary data. Enable delivery only when the camera reports support, before starting its session. Depth-enabled processed capture requests embedding; RAW capture does not request these mattes. A request does not guarantee a matte: the camera must detect a suitable subject.
3. Use Vision accurate person segmentation when no captured portrait matte exists. Combine available hair coverage with the preferred portrait coverage. A coarse Vision mask never replaces an available fine capture portrait matte. These are alpha/coverage images, kept separately from scene depth.
4. **Preserve portrait edges** attenuates near/far blur masks using that coverage. Disable it when the intended focus plane should blur the person too. This protects fractional edges but does not recover true hair geometry or fully remove foreground colour bleeding into the background blur.
5. Persist depth, captured portrait and hair textures locally alongside the original and recipe. Center-cropped capture preserves and crops oriented mattes with the photograph; scalar depth is re-estimated for that framing.

In **Depth**, Analyze generates scene depth and portrait coverage. Inspect **Photo / Depth / Portrait / Hair**; unavailable texture choices are omitted. Hair is available only when Apple supplied a hair matte, not synthesized by Vision. Enable Box select, draw a region and choose Refine selected depth. Disable selection to resume pinch/pan.

## Regional refinement

Choose between two modes after estimating depth and drawing a box:

- **Context crop**: one new inference over the selection with 20% surrounding context. Robust scale/offset fitting aligns it to the existing relative depth; the join is feathered.
- **Overlapping tiles (experimental)**: one contextual inference followed by four overlapping crops, each 68% of the contextual region's width/height (about 36% overlap). Fit the contextual prediction to the saved map, then fit each detail crop to that fixed contextual anchor. Accumulate weighted predictions rather than overwriting tiles in sequence. The anchor retains a baseline weight; support-edge feathering, alignment residual/correlation and per-pixel disagreement reduce unstable contributions. Tile-order independence and exact array preservation outside the selection have dedicated XCTest cases.

Both methods allocate the working grid to the contextual **region**, capped at 2048 pixels on its longest side without upscaling beyond source resolution. This avoids spending most of the grid on the unselected photograph. The resulting regional image blends into the original full-resolution map only inside the selected box. Depth beyond that box and portrait/hair coverage remain unchanged.

Inference uses the bundled Core ML model with all compute units enabled (Core ML chooses scheduling; Neural Engine-only execution is not promised). The same model instance runs sequentially, with one detail tile in flight. Fusion/array alignment executes in Swift on the iPhone CPU and image rendering uses Core Image. No computer, server, network transfer, Python runtime, CUDA or additional model weights are required.

Alignment rejects flat patches, reversed disparity and insufficient context. It uses two-pass 80% residual trimming, positive scale bounds 0.05–20, correlation at least 0.35 and trimmed normalized RMSE at most 0.12. These thresholds and consistency weights are **uncalibrated heuristics**, not learned confidence. A failing tile is omitted and counted; no accepted detail tiles means no saved change. Serious/critical thermal state prevents starting Overlapping tiles; critical heating during the run aborts before the map is replaced. Context crop remains the faster default. This is a still-photo operation, not live video depth.

This original coarse/fine fusion borrows the multi-scale/overlap idea from the literature. It is **not the learned PatchFusion or PatchRefiner V2 architecture**, and no published accuracy/latency claim transfers to it. Crops can lose context or invent depth boundaries; consistency with a wrong coarse map cannot prove geometric accuracy. Hair alpha does not provide hair depth. Inspect seams, glasses, transparency, texture edges and occlusions before using the result. Device benchmarks and paired portrait-quality comparisons remain required.

## Other models

**PatchRefiner V2 (ICLR 2026)** is a newer lightweight refinement candidate; its official inference uses a Python/distributed GPU launcher, and no verified Core ML/iPhone integration is included here. **Prompt Depth Anything** is a promising LiDAR-guided candidate, but no verified Core ML conversion or iPhone benchmark is bundled. It requires calibrated metric LiDAR, which normalized disparity cannot replace. Community Core ML Depth Pro conversions exist, including a pruned/quantized normalized-disparity variant (~745 MB), but no runtime is enabled in this product. The original Apple weight license (AMLR) explicitly excludes product development and commercial products; conversion repository ASCL labels do not override it. Experimental status is not a license exception. MODNet and Robust Video Matting are not bundled; conversions, licensing and device evaluation remain separate work. These methods are not presented as working options.

## Verification and provenance

Apple's unmodified model package and the Small model's Apache 2.0 license are bundled. Source/resource checks run on Windows. Xcode compilation, XCTest, orientation/polarity, capture matte availability, latency, memory, thermals and portrait quality must be checked on an iPhone 16 Pro or newer. No on-device inference or quality benchmark has been run here. The HTML preview uses explicitly labelled illustrative textures and performs no AI inference.

- [Apple Core ML model catalogue](https://developer.apple.com/machine-learning/models/)
- [Depth Anything V2 and Small license](https://github.com/DepthAnything/Depth-Anything-V2)
- [Apple semantic matte capture](https://developer.apple.com/videos/play/wwdc2019/260/)
- [Portrait matte delivery](https://developer.apple.com/documentation/avfoundation/avcapturephotosettings/isportraiteffectsmattedeliveryenabled)
- [Vision person segmentation](https://developer.apple.com/documentation/vision/vngeneratepersonsegmentationrequest)
- [PromptDA](https://github.com/DepthAnything/PromptDA)
- [Apple Depth Pro](https://github.com/apple/ml-depth-pro)

- [PatchFusion coarse/fine learned fusion](https://arxiv.org/abs/2312.02284)
- [PatchRefiner V2 official release and inference](https://github.com/zhyever/PatchRefinerV2)

## Depth Pro assessment (2 October 2026)

The earlier absence-of-conversion assessment was incomplete. A public community conversion exists, but its normalized output is relative inverse depth, not metric metres, and physical-device latency/memory/quality remain unverified here. Apple's code license and model-weight license are distinct. The latter permits only non-commercial scientific research and excludes product development. No Depth Pro weights were downloaded, bundled, installed or enabled. A separate qualifying research project or separately granted model rights would be needed before proceeding. The depth information sheet explains this; a nonworking selectable engine is not added.

- [Community conversion author/model card](https://huggingface.co/KeighBee/coreml-DepthPro)
- [Apple original model-weight license](https://huggingface.co/apple/DepthPro/blob/main/LICENSE)

Editor model status, portrait texture explanations and refinement instructions are available through info buttons. They do not occupy permanent control rows.
