import XCTest
import CoreImage
import UIKit
import SwiftUI
import AVFoundation
@testable import Lutelier

final class RenderTests: XCTestCase {
    func testSliderDetentsAndIntegerAperture() {
        XCTAssertEqual(SliderDetent.value(0.03, in: -3...3, defaultValue: 0), 0)
        XCTAssertEqual(SliderDetent.value(6470, in: 2500...10000, defaultValue: 6500), 6500)
        XCTAssertEqual(SliderDetent.value(0.49, in: 0...1, defaultValue: 0.5), 0.5)
        XCTAssertEqual(SliderDetent.value(0.99, in: 0...1, defaultValue: 1), 1)
        XCTAssertEqual(SliderDetent.value(5.7, in: 3...9, defaultValue: 6, step: 1), 6)
        XCTAssertEqual(SliderDetent.value(0.3, in: 0...1, defaultValue: 0.5), 0.3)
    }
    func testCancelledDepthWorkDoesNotLoadModels() throws {
        let token = DepthCancellation(); token.cancel()
        let photo = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        XCTAssertThrowsError(try LocalDepthModel().estimate(photo, engine: .pro, cancellation: token)) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertThrowsError(try DepthService().analyze(photo, cancellation: token)) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertThrowsError(try LocalDepthModel().refine(photo, region: photo.extent, existing: photo, method: .overlapping, cancellation: token)) { XCTAssertTrue($0 is CancellationError) }
    }
    @MainActor func testCameraDrawerLayouts() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        for expanded in [false, true] {
            window.rootViewController = UIHostingController(rootView: CaptureView(previewOnly: true, showControls: expanded) { _ in })
            window.makeKeyAndVisible(); try await Task.sleep(for: .milliseconds(500))
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            try image.pngData()?.write(to: FileManager.default.temporaryDirectory.appendingPathComponent(expanded ? "camera-drawer.png" : "camera-main.png"))
            let attachment = XCTAttachment(image: image); attachment.lifetime = .keepAlways; add(attachment)
        }
    }

    func testPhotoSelectionAccountsForLetterboxingAndZoom() throws {
        let viewport = CGRect(x: 0, y: 0, width: 400, height: 700)
        let fit = CGRect(x: 0, y: 100, width: 400, height: 500)
        XCTAssertNil(PhotoSelectionGeometry.normalized(CGRect(x: 20, y: 10, width: 30, height: 40), imageFrame: fit, viewport: viewport))
        XCTAssertEqual(PhotoSelectionGeometry.normalized(CGRect(x: 100, y: 50, width: 200, height: 300), imageFrame: fit, viewport: viewport), CGRect(x: 0.25, y: 0, width: 0.5, height: 0.5))
        let zoom = CGRect(x: -200, y: -350, width: 800, height: 1400)
        XCTAssertEqual(PhotoSelectionGeometry.normalized(viewport, imageFrame: zoom, viewport: viewport), CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
    }

    @MainActor func testPortraitCanvasFitsAndComparisonTracksZoom() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 400)).image { context in
            UIColor.orange.setFill(); context.fill(CGRect(x: 0, y: 0, width: 300, height: 400))
        }
        let photo = ZoomPhoto(image: image, visibleRegion: .constant(.zero), before: image)
        let coordinator = photo.makeCoordinator()
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        scroll.minimumZoomScale = 1; scroll.maximumZoomScale = 8; scroll.delegate = coordinator
        scroll.addSubview(coordinator.imageView); coordinator.imageView.addSubview(coordinator.beforeView)
        coordinator.layout(scroll)
        XCTAssertEqual(coordinator.imageView.bounds.width, 390, accuracy: 0.1)
        XCTAssertEqual(coordinator.imageView.bounds.height, 520, accuracy: 0.1)
        XCTAssertEqual(scroll.contentInset.top, 90, accuracy: 0.1)
        XCTAssertEqual(coordinator.photoMask.cornerCurve, .continuous)
        XCTAssertEqual(coordinator.photoMask.cornerRadius, 28)
        XCTAssertEqual(coordinator.photoMask.frame.height, 520, accuracy: 0.1)
        XCTAssertEqual(coordinator.photoMask.frame.width, 390, accuracy: 0.1)
        XCTAssertEqual(coordinator.comparisonMask.frame.width, 195, accuracy: 0.1)
        scroll.setZoomScale(2, animated: false)
        scroll.contentOffset = CGPoint(x: 120, y: 160)
        coordinator.updateComparison(scroll)
        let boundary = coordinator.imageView.convert(CGPoint(x: coordinator.comparisonMask.frame.maxX, y: 0), to: scroll).x - scroll.bounds.minX
        XCTAssertEqual(boundary, 195, accuracy: 0.1, "Comparison must remain at the divider after zoom and pan")
        XCTAssertEqual(coordinator.beforeView.frame, coordinator.imageView.bounds)
    }

    @MainActor func testEditorPortraitLayouts() async throws {
        let store = EditorStore()
        let sourceURL = try XCTUnwrap(Bundle.main.url(forResource: "studio-081", withExtension: "jpg", subdirectory: "Studio"))
        let source = try XCTUnwrap(UIImage(contentsOfFile: sourceURL.path))
        let portrait = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 800)).image { _ in
            let scale = max(600 / source.size.width, 800 / source.size.height)
            let size = CGSize(width: source.size.width * scale, height: source.size.height * scale)
            source.draw(in: CGRect(x: (600 - size.width) / 2, y: (800 - size.height) / 2, width: size.width, height: size.height))
        }
        let filename = "ui-test-\(UUID().uuidString).jpg"
        let url = store.documents.appendingPathComponent(filename)
        try XCTUnwrap(portrait.jpegData(compressionQuality: 0.9)).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        await store.open(PhotoRecord(id: UUID(), filename: filename, date: Date(), recipe: Recipe()))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        for variant in ["editor", "compare", "expanded-looks", "depth", "depth-blur", "depth-lens", "depth-refine", "compact"] {
            let expanded = variant == "compare" || variant == "expanded-looks"
            window.frame = variant == "compact" ? CGRect(x: 0, y: 0, width: 320, height: 568) : scene.coordinateSpace.bounds
            let host = UIHostingController(rootView: EditorView(store: store, expandedPhoto: expanded, comparing: variant == "compare", initialTab: variant.hasPrefix("depth") ? .depth : .looks, initialDepthSection: variant == "depth-blur" ? "Blur" : variant == "depth-lens" ? "Lens" : variant == "depth-refine" ? "Refine" : "Setup"))
            window.rootViewController = host; window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(800))
            host.view.layoutIfNeeded()
            let snapshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let name = "ui-portrait-" + variant
            let attachment = XCTAttachment(image: snapshot); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
            try snapshot.pngData()?.write(to: FileManager.default.temporaryDirectory.appendingPathComponent(name + ".png"))
            XCTAssertGreaterThan(host.view.bounds.height, 500)
        }
    }

    func testBundledDepthModelProducesSceneDepth() async throws {
        try await Task.detached { try Self.verifySceneDepth(engine: .anything) }.value
    }

    func testDepthAnything3ProducesSceneDepth() async throws {
        try await Task.detached { try Self.verifySceneDepth(engine: .anything3) }.value
    }

    func testPortraitDetectionWorksWithoutLoadingDepthModel() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Accurate Vision person segmentation requires the iPhone E5 runtime.")
        #else
        try await Task.detached {
            let url = try XCTUnwrap(Bundle.main.url(forResource: "studio-081", withExtension: "jpg", subdirectory: "Studio"))
            let photo = try XCTUnwrap(CIImage(contentsOf: url, options: [.applyOrientationProperty: true]))
            let result = try DepthService().analyze(photo, engine: .pro, portraitOnly: true)
            XCTAssertNotNil(result.subject, "Apple Vision must detect a portrait independently of the selected depth model")
            XCTAssertNil(result.depth)
            XCTAssertNil(result.hair, "A person mask must not be misrepresented as an Apple hair matte")
        }.value
        #endif
    }

    func testDepthProProducesSceneDepth() async throws {
        guard DepthEngine.pro.isInstalled else { throw XCTSkip("Optional research model is not installed.") }
        try await Task.detached { try Self.verifySceneDepth(engine: .pro) }.value
    }

    private static func verifySceneDepth(engine: DepthEngine) throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "studio-081", withExtension: "jpg", subdirectory: "Studio"))
        let photo = try XCTUnwrap(CIImage(contentsOf: url, options: [.applyOrientationProperty: true]))
        let model = LocalDepthModel()
        let start = Date()
        let map = try model.estimate(photo, engine: engine, progress: { print("Depth phase", $0) })
        print("Depth inference", engine.rawValue, Date().timeIntervalSince(start), "seconds")
        XCTAssertEqual(map.extent, photo.extent)
        let bounds = CGRect(x: 0, y: 0, width: 64, height: 64)
        let fitted = PortraitMatteService.fit(map, to: bounds)
        var pixels = [Float](repeating: 0, count: 64 * 64)
        pixels.withUnsafeMutableBytes {
            CIContext().render(fitted, toBitmap: $0.baseAddress!, rowBytes: 64 * 4, bounds: bounds, format: .Rf, colorSpace: nil)
        }
        XCTAssertTrue(pixels.allSatisfy { $0.isFinite && $0 >= -0.001 && $0 <= 1.001 })
        XCTAssertGreaterThan((pixels.max() ?? 0) - (pixels.min() ?? 0), 0.1)
        let person = try XCTUnwrap(DepthService().analyze(photo, portraitOnly: true).subject)
        var coverage = [Float](repeating: 0, count: 64 * 64)
        coverage.withUnsafeMutableBytes {
            CIContext(options: [.workingColorSpace: NSNull()]).render(PortraitMatteService.fit(person, to: bounds), toBitmap: $0.baseAddress!, rowBytes: 64 * 4, bounds: bounds, format: .Rf, colorSpace: nil)
        }
        let foreground = zip(pixels, coverage).filter { $0.1 > 0.9 }.map { $0.0 }
        let background = zip(pixels, coverage).filter { $0.1 < 0.1 }.map { $0.0 }
        XCTAssertFalse(foreground.isEmpty); XCTAssertFalse(background.isEmpty)
        let foregroundMean = foreground.reduce(0, +) / Float(max(1, foreground.count))
        let backgroundMean = background.reduce(0, +) / Float(max(1, background.count))
        print("Depth foreground/background", engine.rawValue, foregroundMean, backgroundMean)
        XCTAssertGreaterThan(foregroundMean, backgroundMean + 0.1, "The studio portrait must be nearer than its backdrop; also catches vertically flipped or inverted maps")
        let renderer = RenderEngine()
        let depthTexture = try renderer.render(map, recipe: Recipe(), look: .original, depth: nil, maxDimension: 512)
        try XCTUnwrap(depthTexture.pngData()).write(to: FileManager.default.temporaryDirectory.appendingPathComponent("depth-qa-\(engine.modelName).png"))
        let before = try renderer.render(photo, recipe: Recipe(), look: .original, depth: nil, maxDimension: 256)
        var recipe = Recipe(); recipe.farBlur = 0.7; recipe.nearBlur = 0.3; recipe.protectPortraitEdges = false
        let after = try renderer.render(photo, recipe: recipe, look: .original, depth: DepthResult(subject: nil, depth: map, explanation: "Test"), maxDimension: 256)
        XCTAssertNotEqual(try XCTUnwrap(before.pngData()), try XCTUnwrap(after.pngData()), "Scene depth must drive a visible blur render")
    }

    @MainActor
    func testCameraProControlsOnPhysicalDevice() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Manual camera controls require a physical iPhone.")
        #else
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            throw XCTSkip("Authorize camera access in Lutelier before running this hardware test.")
        }
        let camera = CameraService()
        defer { camera.stop() }
        await camera.start()
        for _ in 0..<100 where !camera.ready && camera.error == nil {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(camera.ready, camera.error ?? "Camera did not start")
        guard camera.ready else { return }
        print("Capture capabilities: depth", camera.depthAvailable, "portrait", camera.portraitAvailable, "hair", camera.hairAvailable)
        // Exercise the default virtual camera used when the camera screen opens.
        // The previous implementation aborted the process on entering Pro mode.
        for focus in [0.0, 0.5, 1.0] {
            camera.manual = true
            camera.autoExposure = false; camera.autoFocus = false; camera.autoWhiteBalance = false
            camera.focus = focus
            camera.applyControls()
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertNil(camera.error)
            XCTAssertTrue(camera.session.isRunning)
            camera.manual = false
            camera.applyControls()
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertNil(camera.error)
            XCTAssertTrue(camera.session.isRunning)
        }
        #endif
    }

    @MainActor func testCancelAnalysisKeepsPreviousPortrait() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Vision requires the device E5 runtime.")
        #else
        let store = EditorStore()
        let source = try XCTUnwrap(Bundle.main.url(forResource: "studio-081", withExtension: "jpg", subdirectory: "Studio"))
        let filename = "cancel-test-\(UUID().uuidString).jpg", id = UUID()
        let file = store.documents.appendingPathComponent(filename)
        try Data(contentsOf: source).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        await store.open(PhotoRecord(id: id, filename: filename, date: Date(), recipe: Recipe()))
        await store.analyze(persistMask: false, portraitOnly: true)
        let oldPortrait = try XCTUnwrap(store.portraitPreview)
        store.depthEngine = .anything3
        let work = Task { await store.analyze(persistMask: false, regenerate: true) }
        await Task.yield()
        XCTAssertTrue(store.analysisRunning)
        store.cancelAnalysis()
        await work.value
        XCTAssertFalse(store.analysisRunning); XCTAssertFalse(store.busy)
        XCTAssertFalse(store.hasDepth)
        XCTAssertTrue(store.portraitPreview === oldPortrait)
        XCTAssertNil(store.error)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.documents.appendingPathComponent(id.uuidString + "-depth.png").path))
        #endif
    }
    @MainActor func testLivePhotoCapturePreservesMotionPair() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Live Photos require a physical camera.")
        #else
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { throw XCTSkip("Camera permission required") }
        let camera = CameraService(); defer { camera.stop() }
        await camera.start()
        for _ in 0..<100 where !camera.ready && camera.error == nil { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertTrue(camera.ready, camera.error ?? "Camera not ready")
        guard camera.livePhotoAvailable else { throw XCTSkip("Current lens does not support Live Photos") }
        let completion = expectation(description: "Live Photo pair")
        var capture: CaptureResult?
        camera.onCapture = { result in capture = result; completion.fulfill() }
        camera.useLivePhoto = true; camera.useRAW = false; camera.useHEIF = true
        camera.capture()
        await fulfillment(of: [completion], timeout: 25)
        XCTAssertNil(camera.error)
        let result = try XCTUnwrap(capture)
        let movie = try XCTUnwrap(result.liveMovie)
        defer { try? FileManager.default.removeItem(at: movie) }
        XCTAssertGreaterThan(try Data(contentsOf: movie).count, 1000)
        XCTAssertNotNil(UIImage(data: result.processed))
        #endif
    }

    func testColorCubeChannelOrderAndBundledData() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "presets", withExtension: "json", subdirectory: "Looks"))
        let looks = try JSONDecoder().decode([Look].self, from: Data(contentsOf: url))
        XCTAssertEqual(looks.count, 114)
        let engine = RenderEngine()
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = CIContext(options: [.workingColorSpace: space, .outputColorSpace: space])
        for look in looks {
            let data = try engine.cube(look)
            XCTAssertEqual(data.count, look.dimension * look.dimension * look.dimension * 16)
            let table = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            XCTAssertTrue(table.allSatisfy { $0.isFinite })
            for (r,g,b) in [(1,0,0),(0,1,0),(0,0,1)] {
                let color = CIColor(cgColor: try XCTUnwrap(CGColor(colorSpace: space, components: [CGFloat(r), CGFloat(g), CGFloat(b), 1])))
                let input = CIImage(color: color).cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))
                let output = input.applyingFilter("CIColorCubeWithColorSpace", parameters: ["inputCubeDimension": look.dimension, "inputCubeData": data, "inputColorSpace": space])
                var pixel = [Float](repeating: 0, count: 4)
                pixel.withUnsafeMutableBytes { context.render(output, toBitmap: $0.baseAddress!, rowBytes: 16, bounds: input.extent, format: .RGBAf, colorSpace: space) }
                let index = ((b * (look.dimension - 1) * look.dimension + g * (look.dimension - 1)) * look.dimension + r * (look.dimension - 1)) * 4
                for channel in 0..<3 { XCTAssertEqual(pixel[channel], table[index + channel], accuracy: 0.025, "\(look.id) channel ordering") }
            }
        }
    }

    func testFilmGrainIsRepeatableAndExportKeepsDimensions() throws {
        let image = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 96, height: 64))
        let engine = RenderEngine()
        var recipe = Recipe(); recipe.grain = 0.8
        let first = try engine.render(image, recipe: recipe, look: .original, depth: nil)
        let second = try engine.render(image, recipe: recipe, look: .original, depth: nil)
        let clean = try engine.render(image, recipe: Recipe(), look: .original, depth: nil)
        XCTAssertEqual(first.size.width, 96); XCTAssertEqual(first.size.height, 64)
        XCTAssertEqual(first.pngData(), second.pngData())
        XCTAssertNotEqual(first.pngData(), clean.pngData())
    }

    func testRecipePersistsIndependentNearAndFarSettings() throws {
        var recipe = Recipe(); recipe.nearBlur = 0.25; recipe.farBlur = 0.8; recipe.bokeh = .ring; recipe.light = .rembrandt
        let saved = try JSONEncoder().encode(recipe)
        XCTAssertEqual(try JSONDecoder().decode(Recipe.self, from: saved), recipe)
    }

    func testLegacyRecipeAndNewOpticalSettingsRoundTrip() throws {
        let old = try JSONDecoder().decode(Recipe.self, from: Data("{\"farBlur\":0.8}".utf8))
        XCTAssertEqual(old.farBlur, 0.8)
        XCTAssertEqual(old.apertureBlades, 6)
        XCTAssertEqual(old.highlightSensitivity, 0.7)
        XCTAssertTrue(old.protectPortraitEdges)
        XCTAssertEqual(old.bokehHighlights, 0)
        XCTAssertEqual(old.catEye, 0)
        XCTAssertEqual(old.apertureRotation, 0)
        var recipe = old; recipe.bokeh = .anamorphic; recipe.anamorphicRatio = 2.4; recipe.bokehBloom = 0.5; recipe.bokehHighlights = 0.8; recipe.catEye = 0.6; recipe.apertureRotation = 35
        XCTAssertEqual(try JSONDecoder().decode(Recipe.self, from: JSONEncoder().encode(recipe)), recipe)
    }

    private func opticalPixels(_ image: CIImage) -> [Float] {
        let width = Int(image.extent.width), height = Int(image.extent.height)
        var pixels = [Float](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes {
            CIContext(options: [.workingColorSpace: NSNull()]).render(image, toBitmap: $0.baseAddress!, rowBytes: width * 16,
                bounds: image.extent, format: .RGBAf, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        }
        return pixels
    }

    func testFarBlurDoesNotLeakSubjectColoursAcrossSilhouette() throws {
        let extent = CGRect(x: 0, y: 0, width: 350, height: 120)
        let blue = CIImage(color: CIColor(red: 0, green: 0, blue: 0.8)).cropped(to: extent)
        let box = CGRect(x: 125, y: 0, width: 100, height: 120)
        let image = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: box).composited(over: blue)
        let subject = CIImage(color: .white).cropped(to: box).composited(over: CIImage(color: .black).cropped(to: extent))
        let mask = subject.applyingFilter("CIColorInvert")
        let engine = RenderEngine()
        for style in Bokeh.allCases {
            var recipe = Recipe(); recipe.bokeh = style; recipe.bokehHighlights = 1
            let pixels = opticalPixels(try engine.blur(image, mask: mask, amount: 1, recipe: recipe, subject: subject))
            for x in 226...233 {
                let index = (60*350+x)*4
                XCTAssertLessThan(pixels[index], 0.005, "Subject red must not bleed into background for \(style)")
                XCTAssertGreaterThan(pixels[index+2], 0.75)
            }
            let inside = (60*350+220)*4
            XCTAssertEqual(pixels[inside], 1, accuracy: 0.005)
            XCTAssertEqual(pixels[inside+2], 0, accuracy: 0.005)
        }
    }

    func testNearBlurSpreadsCoverageWithoutLeavingSharpSilhouette() throws {
        let extent = CGRect(x: 0, y: 0, width: 350, height: 120)
        let box = CGRect(x: 125, y: 0, width: 100, height: 120)
        let blue = CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: extent)
        let image = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: box).composited(over: blue)
        let mask = CIImage(color: .white).cropped(to: box).composited(over: CIImage(color: .black).cropped(to: extent))
        let result = try RenderEngine().blur(image, mask: mask, amount: 1, recipe: Recipe(), nearPlane: true)
        let pixels = opticalPixels(result)
        let outside = (60*350+227)*4, inside = (60*350+223)*4
        XCTAssertGreaterThan(pixels[outside], 0.03, "Out-of-focus foreground must spread past its sharp silhouette")
        XCTAssertGreaterThan(pixels[inside+2], 0.03, "Partial occlusion must reveal background at the softened edge")
        XCTAssertTrue(pixels.allSatisfy { $0.isFinite })
    }

    func testDepthOfFieldUsesRadiusRatherThanSharpBlurCrossfade() throws {
        let extent = CGRect(x: 0, y: 0, width: 350, height: 120)
        let black = CIImage(color: .black).cropped(to: extent)
        let image = CIImage(color: .white).cropped(to: CGRect(x: 174, y: 0, width: 2, height: 120)).composited(over: black)
        let mask = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: extent)
        let pixels = opticalPixels(try RenderEngine().blur(image, mask: mask, amount: 1, recipe: Recipe()))
        XCTAssertLessThan(pixels[(60*350+174)*4], 0.4, "Half-depth blur must not retain a 50% sharp copy")
        XCTAssertGreaterThan(pixels[(60*350+171)*4], 0.03)
    }

    func testNearAperturesDoNotLeaveSharpGhostAtHalfDepth() throws {
        let extent = CGRect(x: 0, y: 0, width: 350, height: 120)
        let black = CIImage(color: .black).cropped(to: extent)
        let image = CIImage(color: .white).cropped(to: CGRect(x: 174, y: 0, width: 2, height: 120)).composited(over: black)
        let mask = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: extent)
        for style in Bokeh.allCases {
            var recipe = Recipe(); recipe.bokeh = style
            let pixels = opticalPixels(try RenderEngine().blur(image, mask: mask, amount: 1, recipe: recipe, nearPlane: true))
            XCTAssertLessThan(pixels[(60*350+174)*4], style == .anamorphic ? 0.8 : 0.5, "Near aperture must not retain a sharp copy: \(style)")
        }
    }

    func testDepthOfFieldPortraitEvidence() async throws {
        try await Task.detached {
            let url = try XCTUnwrap(Bundle.main.url(forResource: "studio-081", withExtension: "jpg", subdirectory: "Studio"))
            let image = try XCTUnwrap(CIImage(contentsOf: url))
            #if targetEnvironment(simulator)
            let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("depth-qa-fixture.png")
            guard let map = CIImage(contentsOf: fixture, options: [.colorSpace: NSNull()]) else { throw XCTSkip("Supply a recorded iPhone depth map for simulator photographic QA.") }
            let depth = DepthResult(subject: nil, depth: map, explanation: "Recorded iPhone depth map")
            #else
            let depth = try DepthService().analyze(image, engine: .anything3, requiresDepth: true)
            #endif
            let engine = RenderEngine()
            var recipe = Recipe(); recipe.farBlur = 1; recipe.focusDepth = 0.7
            let enlarged = image.transformed(by: CGAffineTransform(scaleX: 1600 / max(image.extent.width, image.extent.height), y: 1600 / max(image.extent.width, image.extent.height)))
            let start = Date()
            let result = try engine.render(enlarged, recipe: recipe, look: .original, depth: depth, maxDimension: 1800)
            print("DOF render seconds: \(Date().timeIntervalSince(start))")
            try result.pngData()?.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("dof-portrait.png"))
            let attachment = XCTAttachment(image: result); attachment.name = "Occlusion-aware depth of field"; attachment.lifetime = .keepAlways; self.add(attachment)
            XCTAssertEqual(result.size.width / result.size.height, image.extent.width / image.extent.height, accuracy: 0.01)
        }.value
    }

    func testOpticalAperturesPreserveDimUniformBackgrounds() throws {
        let extent = CGRect(x: 0, y: 0, width: 64, height: 64)
        let image = CIImage(color: CIColor(red: 0.1, green: 0.1, blue: 0.1)).cropped(to: extent)
        let mask = CIImage(color: .white).cropped(to: extent)
        let baseline = opticalPixels(image), engine = RenderEngine()
        for style in Bokeh.allCases {
            var recipe = Recipe(); recipe.bokeh = style; recipe.catEye = 0.9
            recipe.apertureRotation = 37; recipe.bokehHighlights = 1; recipe.bokehBloom = 0.6
            let output = opticalPixels(try engine.blur(image, mask: mask, amount: 0.8, recipe: recipe))
            XCTAssertTrue(output.allSatisfy { $0.isFinite })
            for i in output.indices { XCTAssertEqual(output[i], baseline[i], accuracy: 0.002) }
        }
    }

    func testHighlightEnhancementRespectsZeroBlurMask() throws {
        let extent = CGRect(x: 0, y: 0, width: 64, height: 64)
        let dark = CIImage(color: CIColor(red: 0.1, green: 0.1, blue: 0.1)).cropped(to: extent)
        let point = CIImage(color: .white).cropped(to: CGRect(x: 29, y: 29, width: 6, height: 6))
        let image = point.composited(over: dark)
        var recipe = Recipe(); recipe.bokeh = .anamorphic; recipe.bokehHighlights = 1
        recipe.bokehBloom = 0.7; recipe.catEye = 0.5
        let engine = RenderEngine(), baseline = opticalPixels(image)
        let output = opticalPixels(try engine.blur(image, mask: CIImage(color: .black).cropped(to: extent), amount: 1, recipe: recipe))
        for i in output.indices { XCTAssertEqual(output[i], baseline[i], accuracy: 0.002) }
        let white = CIImage(color: .white).cropped(to: extent)
        var neutral = recipe; neutral.bokehHighlights = 0; neutral.bokehBloom = 0
        let without = opticalPixels(try engine.blur(image, mask: white, amount: 1, recipe: neutral))
        let enhanced = opticalPixels(try engine.blur(image, mask: white, amount: 1, recipe: recipe))
        XCTAssertTrue(enhanced.allSatisfy { $0.isFinite })
        XCTAssertTrue(zip(enhanced, without).contains { $0.0 > $0.1 + 0.001 })
    }

    private func matteValue(_ image: CIImage) -> Float {
        var value: Float = 0
        withUnsafeMutableBytes(of: &value) { CIContext(options: [.workingColorSpace: NSNull()]).render(image, toBitmap: $0.baseAddress!, rowBytes: 4, bounds: CGRect(x: floor(image.extent.midX), y: floor(image.extent.midY), width: 1, height: 1), format: .Rf, colorSpace: nil) }
        return value
    }

    func testFineCaptureMatteTakesPriorityOverCoarseVisionMask() throws {
        let extent = CGRect(x: 0, y: 0, width: 64, height: 32)
        func mask(_ value: CGFloat) -> CIImage { CIImage(color: CIColor(red: value, green: value, blue: value)).cropped(to: extent) }
        let subject = try XCTUnwrap(PortraitMatteService.subject(portrait: mask(0.25), hair: mask(0.6), fallback: mask(0.95), extent: extent))
        XCTAssertEqual(matteValue(subject), 0.6, accuracy: 0.015)
        XCTAssertEqual(matteValue(try XCTUnwrap(PortraitMatteService.subject(portrait: nil, hair: nil, fallback: mask(0.95), extent: extent))), 0.95, accuracy: 0.015)
        XCTAssertNil(PortraitMatteService.subject(portrait: nil, hair: nil, fallback: nil, extent: extent))
    }

    func testFractionalHairCoverageReducesBlurWithoutChangingDepth() {
        let extent = CGRect(x: 0, y: 0, width: 64, height: 64)
        let blur = CIImage(color: CIColor(red: 0.8, green: 0.8, blue: 0.8)).cropped(to: extent)
        let hair = CIImage(color: CIColor(red: 0.25, green: 0.25, blue: 0.25)).cropped(to: extent)
        XCTAssertEqual(matteValue(PortraitMatteService.protect(blur, subject: hair)), 0.6, accuracy: 0.015)
        XCTAssertEqual(matteValue(blur), 0.8, accuracy: 0.015)
        XCTAssertEqual(matteValue(PortraitMatteService.protect(blur, subject: nil)), 0.8, accuracy: 0.015)
    }

    func testMatteFitsTranslatedExtentAndProtectedRecipePersists() throws {
        let translated = CIImage(color: .white).cropped(to: CGRect(x: 12, y: 8, width: 10, height: 20))
        let target = CGRect(x: 0, y: 0, width: 80, height: 40)
        XCTAssertEqual(PortraitMatteService.fit(translated, to: target).extent, target)
        var recipe = Recipe(); recipe.protectPortraitEdges = false
        XCTAssertFalse(try JSONDecoder().decode(Recipe.self, from: JSONEncoder().encode(recipe)).protectPortraitEdges)
    }

    func testCenteredCaptureCropKeepsHairCoverageAligned() {
        let full = CGRect(x: 0, y: 0, width: 100, height: 100)
        let black = CIImage(color: .black).cropped(to: full)
        let stripe = CIImage(color: .white).cropped(to: CGRect(x: 30, y: 0, width: 10, height: 100)).composited(over: black)
        let mattes = PortraitMatteService.crop(PortraitMattes(portrait: nil, hair: stripe), imageExtent: full, region: CGRect(x: 25, y: 0, width: 50, height: 100))
        guard let hair = mattes.hair else { return XCTFail("Cropped hair should survive framing") }
        XCTAssertEqual(hair.extent, CGRect(x: 0, y: 0, width: 50, height: 100))
        XCTAssertEqual(matteValue(hair.cropped(to: CGRect(x: 7, y: 40, width: 1, height: 1))), 1, accuracy: 0.015)
        XCTAssertEqual(matteValue(hair.cropped(to: CGRect(x: 20, y: 40, width: 1, height: 1))), 0, accuracy: 0.015)
        XCTAssertNil(mattes.portrait)
    }

    func testDepthPatchAlignsScaleAndPreservesOutsideSelection() throws {
        let w = 60, h = 60, box = CGRect(x: 15, y: 15, width: 30, height: 30)
        let base = (0..<(w*h)).map { Float($0 % w) / Float(w) }
        var local = base.map { ($0 - 0.1) / 2 }
        local[30*w+30] += 0.08
        let result = try DepthPatchFusion.merge(global: base, local: local, width: w, height: h, selection: box, support: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        XCTAssertGreaterThan(result[30*w+30], base[30*w+30] + 0.1)
        for y in 0..<h { for x in 0..<w where !box.contains(CGPoint(x: CGFloat(x), y: CGFloat(y))) {
            XCTAssertEqual(result[y*w+x], base[y*w+x])
        } }
        XCTAssertThrowsError(try DepthPatchFusion.merge(global: base, local: Array(repeating: 0.5, count: w*h), width: w, height: h, selection: box, support: box))
    }

    @MainActor
    func testStudioPromptHonorsIndependentKeepControls() {
        let prompt = StudioStore.generationPrompt(direction: "Soft key light, grey paper, seated three-quarter pose", changePose: false, changeLighting: true, changeBackground: true, changeFraming: false)
        XCTAssertTrue(prompt.contains("keep the source pose and gaze"))
        XCTAssertTrue(prompt.contains("recreate the described studio lighting"))
        XCTAssertTrue(prompt.contains("replace with the described background"))
        XCTAssertTrue(prompt.contains("keep the source framing"))
        XCTAssertTrue(prompt.contains("Do not substitute the reference person's face"))
    }

    func testOverlappingFusionIsOrderIndependentAndPreservesOutsideBox() throws {
        let w = 60, h = 60, support = CGRect(x: 0, y: 0, width: 60, height: 60)
        let selection = CGRect(x: 12, y: 12, width: 36, height: 36)
        let anchor = (0..<(w*h)).map { Float($0 % w) / 100 + Float($0 / w) / 200 }
        var first = anchor.map { $0 / 2 + 0.1 }, second = anchor.map { $0 / 3 + 0.05 }
        first[30*w+30] += 0.03; second[30*w+30] += 0.015
        var forward = DepthPatchFusion.Accumulator(anchor: anchor, width: w, height: h)
        try forward.add(local: first, support: support); try forward.add(local: second, support: support)
        var reverse = DepthPatchFusion.Accumulator(anchor: anchor, width: w, height: h)
        try reverse.add(local: second, support: support); try reverse.add(local: first, support: support)
        let a = forward.finish(original: anchor, selection: selection), b = reverse.finish(original: anchor, selection: selection)
        XCTAssertGreaterThan(a[30*w+30], anchor[30*w+30] + 0.005)
        for i in a.indices {
            XCTAssertTrue(a[i].isFinite); XCTAssertEqual(a[i], b[i], accuracy: 0.00001)
            if !selection.contains(CGPoint(x: CGFloat(i % w), y: CGFloat(i / w))) { XCTAssertEqual(a[i], anchor[i]) }
        }
    }

    func testUnsafeTilesAreRejectedWithoutMutatingFusion() throws {
        let w = 60, h = 60, bounds = CGRect(x: 0, y: 0, width: 60, height: 60)
        let anchor = (0..<(w*h)).map { Float($0 % w) / Float(w) }
        var fusion = DepthPatchFusion.Accumulator(anchor: anchor, width: w, height: h)
        XCTAssertThrowsError(try fusion.add(local: anchor.map { 1 - $0 }, support: bounds))
        XCTAssertThrowsError(try fusion.add(local: [Float](repeating: .nan, count: w*h), support: bounds))
        XCTAssertThrowsError(try fusion.add(local: [Float](repeating: 0.5, count: w*h), support: bounds))
        let unchanged = fusion.finish(original: anchor, selection: bounds)
        for i in anchor.indices { XCTAssertEqual(unchanged[i], anchor[i], accuracy: 0.000001) }
    }

    func testDetailTilesOverlapAndStayInsideTranslatedROI() {
        let roi = CGRect(x: 100, y: 50, width: 600, height: 400)
        let tiles = DepthPatchFusion.tiles(in: roi)
        XCTAssertEqual(tiles.count, 4)
        for tile in tiles { XCTAssertEqual(tile.intersection(roi), tile); XCTAssertLessThan(tile.width, roi.width) }
        XCTAssertFalse(tiles[0].intersection(tiles[1]).isEmpty)
        XCTAssertFalse(tiles[0].intersection(tiles[2]).isEmpty)
    }

    func testStudioLibraryHasOneHundredUniqueCreditedPhotos() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "templates", withExtension: "json", subdirectory: "Studio"))
        let templates = try JSONDecoder().decode([StudioTemplate].self, from: Data(contentsOf: url))
        XCTAssertEqual(templates.count, 100)
        XCTAssertEqual(Set(templates.map(\.sourceURL)).count, 100)
        XCTAssertEqual(Set(templates.compactMap(\.sha256)).count, 100)
        for template in templates {
            XCTAssertFalse(template.author.isEmpty)
            XCTAssertFalse(template.license.isEmpty)
            XCTAssertFalse(template.licenseURL.isEmpty)
            XCTAssertFalse(template.isCustom)
            let imageURL = try XCTUnwrap(Bundle.main.url(forResource: template.file, withExtension: nil, subdirectory: "Studio"))
            XCTAssertNotNil(UIImage(contentsOfFile: imageURL.path))
        }
    }
}
