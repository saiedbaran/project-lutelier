# Lutelier for iPhone

Native SwiftUI iPhone project using your Lutelier icon, the desktop design's amber accent (`#FFB547`), photo-derived backgrounds, and Apple's Liquid Glass controls. This version requires iOS 27 and the Xcode 27 SDK for Studio's on-device multimodal reference analysis. The actual design session identifier `cse_0164rmEvPj6WLCyqaA3rFhRK` was not accessible in this environment; the existing project's documented design tokens and icon were the available references.

**Build status: source and resource validation passed on Windows; native compilation, simulator tests, signing, and physical-device validation are still required. No installable IPA has been built.**

## Open and run on a Mac

1. Transfer this entire folder (or extract `Lutelier-iOS.zip`) to a Mac with Xcode 27 or newer.
2. Open `Lutelier.xcodeproj`. Choose the **Lutelier** scheme.
3. In **Signing & Capabilities**, select your Apple development team. Change `com.saeedsafikhani.lutelier` if necessary to an available bundle identifier. No keys or account credentials are included.
4. Connect your iPhone, enable Developer Mode if requested, choose it as the destination, and Run.
5. On a simulator, use Photos import and the editor. Capture, RAW, sensor depth, and Apple Intelligence must also be checked on compatible hardware.
6. Run Product → Test for the provided rendering tests. From Terminal, `bash tools/build.sh` builds an unsigned simulator app; set `SIMULATOR_ID` to an installed simulator UUID to run tests as well.

The app has no third-party Swift dependencies. The bundled LUTs and Studio references work offline. Foundation Models uses the system-managed on-device model when available; unavailable devices retain manual editing controls. Studio generation uses Apple's in-app Image Playground sheet and may require Private Cloud Compute, network access, Apple Intelligence availability, and system-managed usage allowances.

## Implemented in the source

| Area | Current behavior |
| --- | --- |
| Looks | Original + 114 baked 33³ LUTs: 26 Movies, 21 Cameras, 13 Color film, 11 Black & white, 12 Cinematic, and 31 additional looks. Search includes source descriptions. Previews use the imported photograph. |
| Movie/camera inspiration | Carries the desktop recipes for Blade Runner 2049, Dune, The Matrix, Amélie, The Godfather, Fujifilm, Leica, Hasselblad, Canon, Sony, Nikon, Ricoh, ARRI and others. These are creative emulations, not official manufacturer profiles or licensed studio LUTs. |
| Import | System Photos picker, orientation-aware decoding, local originals and persistent edit recipes. Import custom 3D `.cube` files with 0–1 input domains and dimensions 2–65. |
| Compare | Draggable before/after divider; zoom and pan in the edited view; double-tap zoom/reset. Undo, redo and reset. |
| Grain tab | Amount, size, colour, texture, glow, halation, vignette, and Clean/35mm/Pushed recipes. Grain is repeatable while comparing edits. These are Lutelier effects, not calls to Apple's private Photos rendering pipeline. |
| Pro capture | ISO, shutter, focus, white balance, tint, auto exposure compensation, lens selection, zoom, tap-to-focus in auto, flash, composition grid, live luminance histogram, and 3/10-second timer. Controls follow reported hardware support. |
| RAW | RAW/Apple ProRAW where reported by AVFoundation, with a JPEG companion. DNG files are retained and can be saved to Photos from the editor menu. The initial editor uses the JPEG companion. RAW and depth are mutually exclusive in this first capture implementation. |
| Depth | Reads captured/embedded depth. Uses normalized disparity for independent near/far blur and a movable focus plane. For photographs without depth, bundled Depth Anything V2 Small estimates relative scene depth locally through Core ML. Apple captured portrait/hair mattes protect subject edges; Vision accurate person segmentation provides a fallback. Depth, Portrait and available Hair textures can be inspected separately. All depth processing runs on the iPhone. |
| Regional depth refinement | Show the depth texture, zoom, box-select a region, then choose Refine selected depth. The local model re-estimates a contextual crop, aligns scale/offset and feathers the join. Saved depth survives reopening. Inspect fine edges; accurate hair geometry is not guaranteed. |
| Bokeh | Soft Gaussian, circular disc, ring, anamorphic oval and polygon apertures; separate near/far strengths, oval ratio, blade count, bloom and highlight sensitivity. |
| Studio lighting | Natural, Softbox, Rembrandt, Split, Rim and Stage controls with strength/direction on the captured image. These are 2D subject-mask lighting approximations. |
| Apple Intelligence | Foundation Models interprets a written editing request and returns bounded exposure, white balance, grain and background-blur suggestions. Explicit availability and error handling. The current integration uses editing metadata and text, not visual scene understanding. |
| Studio | New dedicated tab opens a full Studio workspace with 100 real, credited internet reference photographs, categories and search. Add, rename and delete custom reference photos. On-device Foundation Models describes the reference's visible pose, lighting, background and framing. Edit that direction and independently choose what to recreate. Image Playground receives the user's original photo and the reference-derived direction; review the generated result with a before/after slider and keep it as a separate library photo. |
| Export | Full-resolution JPEG saved as a new Photos asset; original preserved. Standard SDR/sRGB output. RAW originals have a separate export command. |

## Advanced work still needed

- The bundled monocular model and regional refinement need device performance and image-quality evaluation. Further learned matting models and geometry-aware relighting remain research work; captured Apple hair mattes and Vision fallback are implemented. Foundation Models is used as an editing assistant, not as a per-pixel depth estimator.
- Real-time relighting, live LUT preview, focus peaking/zebras, hardware aperture control, and HDR/10-bit output are not implemented. The live camera currently shows the native camera preview and exposure histogram; effects are applied after capture.
- Studio lights cannot remove existing cast shadows/reflections. Optical blur can leave edge halos; inspect fine hair and strong highlights on device before treating this as production portrait rendering.
- The desktop's colour LUTs are all retained. Spatial effects not exposed here (dust, scratches, light leaks, anamorphic flare, letterbox) need further native implementation. A LUT cannot contain those effects.
- App Store distribution still needs device QA, signing, release metadata, privacy disclosures, and final icon/UI review. Exports currently do not copy EXIF/GPS metadata from the original.

## Design

The photograph is the central surface. A blurred copy softly colours the background while the actual photograph stays clear. Rounded glass navigation and editor panels float above it, with restrained amber selection outlines and an equal-width six-tab inspector: **Looks · Grain · Depth · Light · Studio · Adjust**. SF Symbols provide familiar iOS controls. The welcome screen uses the iris icon and a bold system headline; the working editor uses system typography and live look thumbnails. Studio opens a spacious reference grid with an expandable selected-template panel. Portrait layout is supported in this version.

The AppIcon asset retains the supplied artwork with its alpha channel removed for iOS packaging. BrandIcon retains the original image. Native appearance, accessibility sizing, and Liquid Glass behavior need simulator/device visual review; they have not been rendered on this Windows host.

## Validation

`validation-report.json` records the checks actually performed: manifest integrity, every LUT's size/checksum/finite RGBA values, source recipe parity at six RGB points, channel ordering, project-file parsing and references, privacy usage strings, and icon dimensions. Native XCTest checks Core Image channel order, grain repeatability, export dimensions, recipe persistence, fractional portrait protection and matte fitting; those tests are provided but have not run here.

To re-export recipes on Windows, run `tools/export_looks.py` with the path to the desktop Python `lutelier` package; NumPy is required. `tools/make_project.py` regenerates the Xcode project and asset manifests. `tools/validate.py` validates the package; optionally pass the desktop package path to also check source parity.

## Apple references

- [Liquid Glass in SwiftUI](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:))
- [AVFoundation depth capture](https://developer.apple.com/documentation/avfoundation/avcapturedepthdataoutput)
- [Person segmentation](https://developer.apple.com/documentation/vision/vngeneratepersonsegmentationrequest)
- [Foundation Models](https://developer.apple.com/documentation/foundationmodels)
- [iPhone Photographic Styles](https://support.apple.com/en-mt/guide/iphone/iph629d2cd37/ios)
- [Image Playground integration and availability](https://developer.apple.com/documentation/imageplayground)
- [Foundation Models multimodal reference analysis](https://developer.apple.com/documentation/foundationmodels/analyzing-images-with-multimodal-prompting)

## Studio behavior and limits

Studio remains inside Lutelier. Reference analysis runs on the device. Photorealistic generation is an Apple-managed Image Playground experience that may run on Private Cloud Compute. The user reviews and confirms the generated image inside that sheet, then reviews it again in Lutelier before keeping it. The app does not implement a separate cloud API, use private Apple APIs, or silently send photos to another provider. The selected generation style is inferred from the photographic prompt; third-party-provider styles are not enabled by this app.

The current public Image Playground flow seeds one source image. Lutelier seeds the user's photograph and uses on-device analysis to translate the template into a textual photographic direction. It does **not** directly feed both images into a pose-conditioned image-to-image model. Exact pose transfer, background replication, face identity preservation, studio-light accuracy and photorealism are not guaranteed. These need device evaluation and, for tighter control, a dedicated reference-conditioned image-editing model. Foundation Models can analyze reference photographs but does not generate the finished image.

Custom templates stay in the app's local documents directory. Their descriptions are saved after analysis or generation preparation. Generated image bytes are copied immediately from Apple's temporary completion URL; keeping creates a new record with source-photo ID, template ID and an AI-generated flag. Discarding removes the pending generated file. Originals are never overwritten. Generation resolution is managed by Image Playground and can differ from the original capture's resolution.

See `STUDIO-CREDITS.md` for photo-level attributions and licenses. Bundled references are licensed individually; their presence does not imply endorsement by the photographer or depicted person. Generated outputs do not include the reference person's identity intentionally. Reference photos are aesthetic examples, not training data. Any rights that may apply to a particular generated adaptation remain subject to the underlying reference license.

Look changes use a 360 ms cross-dissolve. The caption is above all overlays. The tool island fits its contents, with a separate camera button. Rounded photo corners and local photo-coloured backlighting frame the image. See [local depth implementation and research](DEPTH-REFINEMENT.md) for model provenance, limitations and testing requirements.

The launch screen shows a large lens logo, bold LUTELIER name and “The art of photography”, then fades into the workspace. The common toolbar island is anchored left and fits its contents; the independent camera remains right-aligned. A clipped blurred photo backdrop fills the entire screen, including the status and home-indicator areas. The camera shadow follows motion (pointer movement in the browser, granted device orientation on Safari, Core Motion natively) and blends into an icon-coloured glow while pressed, then returns on release or cancellation. Tool tabs use a movable glass highlight; hold and slide to preview a destination, release to select. The native highlight uses SwiftUI glassEffect; the browser approximates it with translucent blur and edge reflections. Native visual and gesture behavior requires device testing.

## Updated controls and advanced depth

Looks uses swipeable category buttons and a lower Liquid Glass Strength thumb, with no description beneath. Main tabs have equal widths and bold selection. Launch tagline is closer and all caps.

Depth runs entirely on the iPhone: bundled Depth Anything V2 Small for scene depth, captured Apple portrait/hair mattes for fine coverage, and Vision accurate person segmentation as fallback. Saved refined maps survive reopening. Preserve portrait edges controls how coverage attenuates optical blur. No computer companion is included. PromptDA and Depth Pro remain unverified research candidates, not selectable engines. See [on-device implementation](DEPTH-REFINEMENT.md). Native build and physical-device quality/performance testing remain required.
