# Lutelier interactive design

Open `Lutelier-interactive.html` for a single-file offline preview with all code, icons and photographs embedded. `index.html` is the editable multi-file version. All 114 predefined look names and 100 credited reference photographs are bundled locally. The default image is from the credited Studio collection.

For browser camera access, run `node LutelierPreview/serve.cjs` from the parent workspace, open `http://127.0.0.1:8765`, then choose **Camera → Enable live camera**. Imported photographs and custom references stay in this page's memory and disappear on reload. Export downloads a JPEG treatment. For export from a directly opened file, use the standalone HTML with embedded photos.

The iOS app icon uses the supplied opaque artwork. The camera control uses the separately supplied transparent lens artwork in its original colours. It has transparent surroundings and a shadow that follows pointer movement or device tilt. The header has a text-only LUTELIER wordmark in the Apple system font's Heavy weight (800 in CSS). On Safari, use **Enable tilt shadow** (also in Options) to grant motion access. Reduced-motion preferences keep the shadow still and skip look animations.

The camera is 68px wide, separated by 14px from the common toolbar island. The island radius is calculated from the phone's outer corner radius minus its screen inset. Scrollbars are hidden throughout; touch swipes, trackpads, mouse wheels and dragging the horizontal rows remain available.

Typography uses the Apple system font stack: San Francisco on Apple devices, a system fallback on Windows. The bold wordmark is uppercase LUTELIER. Native icons use SF Symbols; the browser uses matching vector icons rather than distributing Apple's platform-specific symbol font. Look changes crossfade over 360 ms with no moving glass cover. The caption stays above all photo overlays. The tool island fits its button count; photo corners follow the phone inset; a blurred, colour-treated copy produces ambient backlighting. Double-tap, pinch, pan and mouse-wheel zoom are supported.

The browser uses approximate CSS colour treatments and blur, not the native 3D LUT pipeline. Pro capture controls, RAW, subject depth masks, bokeh shapes, Foundation Models and Image Playground are design demonstrations. Studio result previews apply a colour treatment to the source and do not generate a new pose, background or identity. Camera capture saves a JPEG regardless of the RAW demonstration toggle.

No web fonts are downloaded. No imported photograph is uploaded. Individual Studio credits are available in the selected reference and Options → Photo credits.

The native implementation uses Apple's [Core Motion](https://developer.apple.com/documentation/coremotion/cmmotionmanager/startdevicemotionupdates(to:withhandler:)) and [Liquid Glass](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)) APIs. Native compilation and motion behavior must still be verified in Xcode on a supported iPhone.

Pressing the camera lens rotates it 90 degrees over 160 ms. Moving outside its circular hit area or canceling the pointer returns it and prevents camera activation. Releasing inside opens the camera; closing the camera resets the lens. Reduced motion disables the rotation animation. The native button uses SwiftUI pressed-state handling and still needs device verification.

Camera opens in Auto with the settings panel collapsed. Enabling Pro reveals the histogram, RAW, flash, manual exposure/focus/white balance, depth, zoom and timer settings; disabling Pro hides the panel again.


Camera controls: the bottom-left PRO button opens and closes the settings, and the bottom-right picker offers 4:3, 1:1, 16:9 and Full Screen. Portrait framing and processed JPEG capture use the chosen crop. The top icon row controls live camera, grid, flash, timer and front/rear camera. Browser flash is a native-feature demonstration. Native RAW preserves the full sensor original; cropped JPEG scalar depth is re-estimated on-device; captured portrait/hair mattes are cropped with the photograph.

Depth includes anamorphic and polygon aperture settings, bloom, highlight sensitivity, a labelled illustrative depth texture and box selection. Native Core ML inference is implemented in the iOS project; no AI inference runs in this HTML. See ../LutelierIOS/DEPTH-REFINEMENT.md.

The launch screen shows a large lens logo, bold LUTELIER name and “The art of photography”, then fades into the workspace. The common toolbar island is anchored left and fits its contents; the independent camera remains right-aligned. A clipped blurred photo backdrop fills the entire screen, including the status and home-indicator areas. The camera shadow follows motion (pointer movement in the browser, granted device orientation on Safari, Core Motion natively) and blends into an icon-coloured glow while pressed, then returns on release or cancellation. Tool tabs use a movable glass highlight; hold and slide to preview a destination, release to select. The native highlight uses SwiftUI glassEffect; the browser approximates it with translucent blur and edge reflections. Native visual and gesture behavior requires device testing.

Looks uses swipeable categories, lower glass-style Strength and equal-width tabs with bold selection. Launch tagline is closer and all caps. Depth shows the on-device Core ML + Apple portrait/hair pipeline, portrait protection and labelled illustrative texture choices. Native Hair is only available when a photo contains an Apple hair matte; the browser illustrations do not reflect real detected geometry. This HTML preview performs no depth inference.

Depth exposes Context crop and experimental Overlapping tiles, corresponding to the native iPhone pipeline. The latter uses one contextual + four sequential Core ML detail crops and consistency-weighted fusion on a bounded regional grid. The browser only demonstrates the controls; it never estimates or refines actual depth. Native visual quality and speed have not been measured on device.

Editor descriptions and method explanations are behind accessible info buttons. The depth panel leads with Analyze, aperture choices and sliders; texture and refinement controls follow below. Information opens inside the phone preview and Done returns to the same editing state. The Depth models information explains why research-only Depth Pro weights are not enabled in Lutelier.
