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

The same bundled model re-estimates a crop with 20% surrounding context. Two-pass robust scale/offset alignment reconciles its relative values with the existing texture. Flat or conflicting patches are rejected, the boundary is feathered, and full-resolution pixels outside the selection are preserved. Fusion uses a bounded 2048-pixel working grid. Portrait/hair coverage remains separate and unchanged.

This is contextual crop refinement, not the learned PatchFusion architecture. A crop can lose context or invent edges. Inspect seams, hair, glasses, transparency and occlusions before relying on it.

## Other models

Prompt Depth Anything is a promising LiDAR-guided candidate, but no verified Core ML conversion or iPhone benchmark is bundled. It requires calibrated metric LiDAR, which normalized disparity cannot replace. Depth Pro has no verified runtime in this app. MODNet and Robust Video Matting are not bundled; conversions, licensing and device evaluation remain separate work. These methods are not presented as working options.

## Verification and provenance

Apple's unmodified model package and the Small model's Apache 2.0 license are bundled. Source/resource checks run on Windows. Xcode compilation, XCTest, orientation/polarity, capture matte availability, latency, memory, thermals and portrait quality must be checked on an iPhone 16 Pro or newer. No on-device inference or quality benchmark has been run here. The HTML preview uses explicitly labelled illustrative textures and performs no AI inference.

- [Apple Core ML model catalogue](https://developer.apple.com/machine-learning/models/)
- [Depth Anything V2 and Small license](https://github.com/DepthAnything/Depth-Anything-V2)
- [Apple semantic matte capture](https://developer.apple.com/videos/play/wwdc2019/260/)
- [Portrait matte delivery](https://developer.apple.com/documentation/avfoundation/avcapturephotosettings/isportraiteffectsmattedeliveryenabled)
- [Vision person segmentation](https://developer.apple.com/documentation/vision/vngeneratepersonsegmentationrequest)
- [PromptDA](https://github.com/DepthAnything/PromptDA)
- [Apple Depth Pro](https://github.com/apple/ml-depth-pro)
