# Native validation required

No item below has been marked passed on this Windows host. Run these checks on the Mac/iPhone before distribution.

- Build the shared Lutelier scheme, run RenderTests, and review compiler diagnostics.
- Confirm the supplied icon, dark portrait layout, Liquid Glass controls, safe-area spacing, and thumbnails on iPhone 18 Pro and a smaller supported iPhone. Test Dynamic Type, VoiceOver, Reduce Transparency, and Reduce Motion.
- Import an iCloud photo, an ordinary JPEG, a HEIC, an EXIF-rotated image, a Portrait-mode photo, and a large 48MP photo. Check depth/photo alignment for every rotation. Switch photos while rendering and while generating thumbnails.
- Compare Original to an untouched photo; drag the split, zoom/pan, choose multiple movie/camera looks, adjust strength, undo/redo, and relaunch. Confirm stored edits and refined masks survive reopening.
- Test camera denied access and authorized access, front/back lenses, every exposed manual control, lens switching, flash, tap focus, histogram, timer dismissal, app backgrounding, and repeated captures. Hardware aperture control is not part of this version.
- Capture JPEG with depth and RAW with its JPEG companion. Confirm original DNG preservation/export, capability gating, and recovery when capture fails. RAW editing currently uses the processed companion.
- Inspect hair, glasses, semi-transparent edges, foreground occluders, strong highlights and background blur. Confirm near/far separation only claims captured depth. Refine the zoomed region and reopen the image.
- Evaluate all studio-light presets at multiple angles and powers. Check mask halos and clipping. Lighting reconstruction and live relighting remain future work.
- Test Foundation Models with Apple Intelligence enabled, disabled, unsupported hardware, an unavailable language, and a refused request. Inspect suggestions and verify undo returns the previous recipe.
- Export to Photos with permission granted and denied; confirm dimensions, color, repeatable grain, original preservation and SDR output. Measure time, memory, battery and thermal load for 48MP exports.
- Studio: confirm exactly 100 local reference photos load offline with correct credits/license links; category/search selection and scrolling must remain responsive. Add, rename and delete a custom template; restart and verify persistence.
- Analyze Studio references on supported iOS 27 Apple Intelligence hardware, including a custom photo, with unavailable settings and with a refused request. Verify a canceled or replaced request never overwrites a newer template's direction. Inspect all pose/light/background/framing descriptions for accuracy.
- Generate in the in-app Image Playground sheet with each recreate switch enabled/disabled. Evaluate photorealism, facial identity, pose transfer, background, hands and light separately. Test system cancellation, network loss and exhausted system allowance. No visual quality guarantee has been validated on this Windows host.
- Confirm generated completion data is copied before the temporary URL expires. Compare, discard, retry, keep, reopen and export. A kept portrait must be a separate library record linked to its source/template and labeled AI-generated; the source and prior recipe must remain intact.
