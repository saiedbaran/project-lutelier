# Optional local depth companion

The iPhone default remains Core ML Depth Anything V2 Small. This companion implements **PatchFusion**, **Depth Anything 3** and **Apple Depth Pro** adapters through the authors' PyTorch implementations. Full photos or selected crops run on your own computer. This is not an on-device PatchFusion conversion. No companion weights are bundled.

## Setup

1. Install the [official PatchFusion environment](https://github.com/zhyever/PatchFusion), including its external dependencies, on a CUDA computer. Run official single-image inference once with `Zhyever/patchfusion_depth_anything_vits14` to cache all required weights/configs. The tester hardcodes CUDA. Linux/WSL with CUDA is the intended host; an ordinary iPhone or Mac-only setup cannot execute this adapter.
2. Optionally install [Depth Anything 3](https://github.com/ByteDance-Seed/Depth-Anything-3) in a separate environment and cache **DA3-SMALL** (or Base) in a local directory containing config/safetensors. Small/Base weights use Apache 2.0; other variants have different terms. For [Depth Pro](https://github.com/apple/ml-depth-pro), follow its install/checkpoint instructions: `checkpoints/depth_pro.pt` must exist in its repo. Review every code/weight license for intended use.
3. Install `requirements.txt` in a lightweight server environment. Copy `config.example.json` to **config.local.json** and replace the absolute Python/repo/weight paths. Remove unwanted entries. Windows JSON paths need escaped backslashes or forward slashes. Configured does not mean inference-tested.
4. Set environment variable `LUTELIER_DEPTH_TOKEN` to an ASCII secret at least 24 characters long. Run `python server.py --config config.local.json`. Default: loopback `127.0.0.1:8770`. For iPhone access, explicitly bind to your computer's private LAN IP with `--host 192.168.1.20` (replace with the real address), allowing access only on your trusted private network. Use a trusted HTTPS reverse proxy for encrypted transport. Do not expose this server publicly. HTTP sends photos and the token unencrypted on that LAN.
5. Open **Depth → Advanced models · local computer** in Lutelier, enter address/token, and Connect. Select a configured engine, then **Estimate scene depth**, or draw a region and **Refine selected depth**. Both devices need the same network; grant iOS local-network access. A phone's `127.0.0.1` refers to the phone, not your computer.

Only explicit Estimate/Refine actions send images. Automatic capture/library analysis stays on-device. Credentials stay in memory for the app session. Images use temporary files that are cleaned up; request logging is disabled. Both endpoints require the token. The app accepts private IPv4/`.local` hosts, rejects redirects and preserves TLS validation. Changing address/token resets available engines. No browser CORS access is enabled.

## Contract

- Authenticated `GET /v1/engines`: capability list with `configured`, `verified: false` and setup detail.
- Authenticated `POST /v1/depth`: JSON with `engine` and base64 `image`; returns engine, convention `relative-near-white`, base64 16-bit grayscale PNG, width/height.
- PatchFusion invokes `tools/test.py`, general inference, shifted tiles (`m2`), 2×2 splits and one patch per batch. Official `photo_uint16.png` stores depth ×256. Colourised output is rejected. Input sizes round down to multiples of four and the iPhone fits the map back to the photo extent.
- DA3/Depth Pro use public Python APIs in isolated subprocesses. Output depth is inverted and percentile-normalized so white is near. This output is relative even when the source model predicts metres.
- Crops include 20% context; native robust scale/offset alignment and feathering preserve the old texture outside the selected box. This merge is separate from PatchFusion's learned tile-fusion network. Flat/conflicting patches are rejected.
- One inference at a time, 600-second model timeout, 32 MB request/24 MP input limits. Fixed subprocess arguments, no shell. `HF_HUB_OFFLINE` and `TRANSFORMERS_OFFLINE` prevent automatic downloads; cache weights beforehand.

## Verification

Run `python -m unittest -v test_server.py`. Eleven Windows contract tests passed: auth, routing, size limits, unavailable engines, depth polarity, 16-bit roundtrip, official CLI arguments, raw output parsing, invalid-map rejection and lock cleanup. Tests use synthetic maps and mocked model execution. **Real model inference, GPU compatibility and iPhone integration are untested here**: this host has no installed PyTorch/CUDA environment or Xcode. Pin upstream revisions after full-image and crop inference verification.
