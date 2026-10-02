# Local depth and selected-area refinement

The bundled model is Apple's Core ML conversion of **Depth Anything V2 Small F16** (approximately 50 MB). It estimates relative disparity for arbitrary photographs, with white nearer and black farther away. It does not measure metres. Captured portrait disparity remains the first choice when present. Person segmentation is stored separately and is used for subject-aware lighting; it is not labelled as depth.

In **Depth**, estimate the scene, enable **Show depth texture**, zoom to inspect it, enable **Box select**, draw a region, and choose **Refine selected depth**. Turn off Box select to resume pinch/pan. The operation runs locally through Core ML and Vision, not Foundation Models or Image Playground.

The selected crop includes 20% surrounding context. Running the same model on that crop gives the selected subject more of the model's input resolution. Two-pass robust scale/offset alignment reconciles the crop's relative values with the existing texture. Flat or conflicting patches are rejected, the boundary is feathered, and the original full-resolution texture outside the selection is preserved. Fusion uses a bounded 2048-pixel working grid to control memory; the result and saved texture return to the image extent.

This is a practical first implementation of regional refinement, not the learned PatchFusion architecture. A crop can also lose scene context or invent depth edges. Inspect the texture and the rendered blur before relying on it. Thin hair, glass, transparency and occlusions need particular care. Higher-resolution depth is not equivalent to a high-quality hair alpha matte.

## Research direction

For the next quality step, evaluate a learned tile-fusion model against this baseline, then combine depth with a dedicated fine-edge portrait matte and captured disparity as an anchor. Require confidence-aware rejection and compare patches on full-resolution portraits containing flyaway hair, glasses, overlapping objects and point lights. Choose that more complex pipeline only after measuring edge accuracy, seam error, memory, latency and thermals on the target iPhone.

- [Apple's Core ML model catalogue](https://developer.apple.com/machine-learning/models/): official iPhone-ready Depth Anything V2 Small conversion.
- [Depth Anything V2](https://github.com/DepthAnything/Depth-Anything-V2): Small weights use Apache 2.0; larger variants have different terms. The Small license is included in Resources/Models/LICENSE-DepthAnything.txt.
- [PatchFusion, CVPR 2024](https://github.com/zhyever/PatchFusion): optional authenticated companion adapter invokes official CUDA tile inference. Weights are not bundled; published results have not been reproduced here.
- [Apple Depth Pro](https://github.com/apple/ml-depth-pro): companion adapter uses its public Python API; separate weights, licensing and platform evaluation required.

The model package was downloaded unmodified from Apple's ml-assets.apple.com catalogue. Xcode compilation, output orientation, depth polarity, inference performance and visual quality must be verified on a Mac/iPhone. The Windows resource checks do not execute Core ML. The HTML preview deliberately uses a labelled illustrative texture and does not run local AI inference.

## Advanced methods reviewed on 2 October 2026

This is a curated comparison, not every published depth method. **My next evaluation choice for crop detail is PatchRefiner V2 against PatchFusion and the bundled baseline.** That recommendation is an inference from architecture and release scope, not a measured win on Lutelier portraits. Benchmark hair, transparent glasses, occlusions and bokeh lights first.

| Method | Relevant capability | Lutelier status |
| --- | --- | --- |
| [PatchFusion](https://github.com/zhyever/PatchFusion), CVPR 2024 | Learned coarse/fine tile fusion | Companion implemented; separate CUDA environment/weights; GPU inference untested |
| [PatchRefiner V2](https://github.com/zhyever/PatchRefinerV2), ICLR 2026 | Fast real-domain high-resolution refinement; official full release 17 February 2026 | Research watchlist; no adapter/Core ML conversion. Checkpoint terms need review; repository listing shows no license file |
| [Depth Anything 3](https://github.com/ByteDance-Seed/Depth-Anything-3), November 2025 | Single/multi-view depth and geometry | Companion implemented; local Small/Base Apache 2.0 weights; no iPhone conversion |
| [Apple Depth Pro](https://github.com/apple/ml-depth-pro), ICLR 2025 | Sharp metric depth and focal estimation | Companion implemented; Apple code/weight terms and performance need review |
| [PRO / One Look is Enough](https://github.com/KAIST-VICLab/One-Look-is-Enough), ICCV 2025 | Seamless zero-shot patchwise refinement | Research only: authors explicitly require permission for commercial code/checkpoint use |
| [PromptDA](https://github.com/DepthAnything/PromptDA), CVPR 2025 | High-resolution depth guided by sparse metric LiDAR; transparent-object Small variant | Research watchlist; needs retained calibrated LiDAR and an adapter. Normalized disparity/segmentation cannot replace the metric prompt |
| [PromptDA++](https://github.com/DepthAnything/PromptDA) | Announced successor | Official news currently says code/models will be released; watchlist only |
| [Marigold](https://github.com/prs-eth/Marigold), CVPR 2024 and later releases | Diffusion-derived depth baseline | Watchlist; no adapter/mobile optimization/latency benchmark included |

Native Depth exposes the implemented engines and companion setup. The browser explores these methods and their status without AI inference. See [DepthCompanion/README.md](DepthCompanion/README.md) for setup and protocol. Selecting an engine never automatically downloads weights or sends a photo.
