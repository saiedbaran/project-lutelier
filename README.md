# Lutelier

Creative photography app for iPhone: cinematic and camera-inspired looks, film grain, depth and lighting controls, Pro capture, and Studio reference workflows.

- **Native app:** Open `LutelierIOS/Lutelier.xcodeproj` on a Mac with Xcode 27. See [build instructions and feature status](LutelierIOS/README.md).
- **Interactive design:** Run `node LutelierPreview/serve.cjs`, then open http://127.0.0.1:8765/Lutelier-interactive.html. The standalone HTML also works offline.
- **Resources:** 114 LUTs and 100 attributed Studio reference photographs. See [Studio credits](LutelierIOS/STUDIO-CREDITS.md).

The browser prototype demonstrates the design and approximates photo effects; Studio previews do not generate new poses or identities. Native source and resources are validated on Windows, but compilation, signing, and device testing still require Xcode and a supported iPhone. The app uses the supplied Lutelier artwork: an opaque app icon and a transparent camera icon.

Regenerate the standalone preview with `node LutelierPreview/bundle.cjs`. Run `python LutelierIOS/tools/validate.py` for resource and project checks, and `python LutelierIOS/tools/package.py` to generate the iOS source archive.
