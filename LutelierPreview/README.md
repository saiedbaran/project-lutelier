# Lutelier interactive design

Open `Lutelier-interactive.html` for a single-file offline preview with all code, icons and photographs embedded. `index.html` is the editable multi-file version. All 114 predefined look names and 100 credited reference photographs are bundled locally. The default image is from the credited Studio collection.

For browser camera access, run `node LutelierPreview/serve.cjs` from the parent workspace, open `http://127.0.0.1:8765`, then choose **Camera → Enable live camera**. Imported photographs and custom references stay in this page's memory and disappear on reload. Export downloads a JPEG treatment. For export from a directly opened file, use the standalone HTML with embedded photos.

The iOS app icon uses the supplied opaque artwork. The camera control uses the separately supplied transparent lens artwork in its original colours. It has transparent surroundings and a shadow that follows pointer movement or device tilt. The header has a text-only LUTELIER wordmark in the Apple system font's Heavy weight (800 in CSS). On Safari, use **Enable tilt shadow** (also in Options) to grant motion access. Reduced-motion preferences keep the shadow still and skip look animations.

The camera is 68px wide, separated by 14px from the common toolbar island. The island radius is calculated from the phone's outer corner radius minus its screen inset. Scrollbars are hidden throughout; touch swipes, trackpads, mouse wheels and dragging the horizontal rows remain available.

Typography uses the Apple system font stack: San Francisco on Apple devices, a system fallback on Windows. The bold wordmark is uppercase LUTELIER. Native icons use SF Symbols; the browser uses matching vector icons rather than distributing Apple's platform-specific symbol font. Look changes bring a photo-sized glass cover carrying the upcoming treatment from outside the image boundary, with perspective, rotation and depth. The cover settles exactly over the photo, blends into the next look, loses its blur and reflections, and fades away over the sharp result. Rapid selections cancel earlier pending changes. Native transitions prepare the incoming render before showing the cover.

The browser uses approximate CSS colour treatments and blur, not the native 3D LUT pipeline. Pro capture controls, RAW, subject depth masks, bokeh shapes, Foundation Models and Image Playground are design demonstrations. Studio result previews apply a colour treatment to the source and do not generate a new pose, background or identity. Camera capture saves a JPEG regardless of the RAW demonstration toggle.

No web fonts are downloaded. No imported photograph is uploaded. Individual Studio credits are available in the selected reference and Options → Photo credits.

The native implementation uses Apple's [Core Motion](https://developer.apple.com/documentation/coremotion/cmmotionmanager/startdevicemotionupdates(to:withhandler:)) and [Liquid Glass](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)) APIs. Native compilation and motion behavior must still be verified in Xcode on a supported iPhone.

Pressing the camera lens rotates it 90 degrees over 160 ms. Moving outside its circular hit area or canceling the pointer returns it and prevents camera activation. Releasing inside opens the camera; closing the camera resets the lens. Reduced motion disables the rotation animation. The native button uses SwiftUI pressed-state handling and still needs device verification.

Camera opens in Auto with the settings panel collapsed. Enabling Pro reveals the histogram, RAW, flash, manual exposure/focus/white balance, depth, zoom and timer settings; disabling Pro hides the panel again.


Camera controls: the bottom-left PRO button opens and closes the settings, and the bottom-right picker offers 4:3, 1:1, 16:9 and Full Screen. Portrait framing and processed JPEG capture use the chosen crop. The top icon row controls live camera, grid, flash, timer and front/rear camera. Browser flash is a native-feature demonstration. Native RAW preserves the full sensor original; cropped JPEG depth masks are rebuilt using Vision instead of reusing misaligned sensor depth.
