import SwiftUI
import PhotosUI
import Photos
import CoreImage
import AVFoundation
import UniformTypeIdentifiers
import ImageIO

@MainActor
final class EditorStore: ObservableObject {
    @Published var looks: [Look] = [.original]
    @Published var photos: [PhotoRecord] = []
    @Published var recipe = Recipe()
    @Published var originalPreview: UIImage?
    @Published var preview: UIImage?
    @Published var renderedLookID = "original"
    @Published var thumbnails: [String: UIImage] = [:]
    @Published var depthStatus = "Analyze a portrait to unlock depth tools"
    @Published var hasDepth = false
    @Published var hasSubject = false
    @Published var depthPreview: UIImage?
    @Published var portraitPreview: UIImage?
    @Published var hairPreview: UIImage?
    @Published var matteStatus = "Analyze to find portrait edges"
    @Published var depthEngine: DepthEngine = .anything
    @Published var depthRefinementMethod: DepthRefinementMethod = .contextual
    private var capturedMattes = PortraitMattes()
    @Published var analysisRunning = false
    @Published var cancellingAnalysis = false
    private var depthCancellation: DepthCancellation?
    func cancelAnalysis() {
        guard analysisRunning else { return }
        depthCancellation?.cancel(); cancellingAnalysis = true
        depthStatus = "Cancelling after the current model pass…"
    }
    @Published var busy = false
    @Published var error: String?
    @Published var message: String?
    @Published var assistantPrompt = ""
    @Published var assistantBusy = false
    @Published var selectedPhotoID: UUID?
    private var original: CIImage?
    private var depth: DepthResult?
    private var history: [Recipe] = []
    private var future: [Recipe] = []
    private var renderTask: Task<Void, Never>?
    private var generation = 0
    private let worker = DispatchQueue(label: "lutelier.render", qos: .userInitiated)
    private let engine = RenderEngine()
    private let depthService = DepthService()
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    var currentLook: Look { looks.first(where: { $0.id == recipe.lookID }) ?? .original }
    var canUndo: Bool { !history.isEmpty }
    var canRedo: Bool { !future.isEmpty }
    var hasPhoto: Bool { original != nil }

    init() {
        do {
            guard let url = Bundle.main.url(forResource: "presets", withExtension: "json", subdirectory: "Looks") else { throw LutelierError.message("The built-in look library is missing.") }
            looks += try JSONDecoder().decode([Look].self, from: Data(contentsOf: url))
            if let data = try? Data(contentsOf: documents.appendingPathComponent("library.json")) { photos = try JSONDecoder().decode([PhotoRecord].self, from: data) }
            if let data = try? Data(contentsOf: documents.appendingPathComponent("imported-looks.json")) { looks += try JSONDecoder().decode([Look].self, from: data) }
        } catch { self.error = error.localizedDescription }
    }

    func importPhoto(_ item: PhotosPickerItem) async {
        busy = true
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { throw LutelierError.message("This photograph could not be loaded from Photos.") }
            try await add(data: data)
        } catch { self.error = error.localizedDescription; busy = false }
    }
    func receiveCapture(_ result: CaptureResult) async {
        do {
            try await add(data: result.processed, raw: result.raw, captured: result.depth, mattes: result.orientedMattes ?? PortraitMatteService.read(result.processed, portrait: result.portrait, hair: result.hair), liveMovie: result.liveMovie)
            if let recipe = result.initialRecipe { edit { $0 = recipe } }
        }
        catch { self.error = error.localizedDescription; busy = false }
    }
    func receiveStudioResult(_ data: Data, request: StudioGenerationRequest) async -> Bool {
        busy = true
        do {
            guard CIImage(data: data, options: [.applyOrientationProperty: true]) != nil else { throw LutelierError.message("The generated portrait could not be decoded.") }
            let id = UUID(), filename = UUID().uuidString + ".photo"
            try data.write(to: documents.appendingPathComponent(filename), options: .atomic)
            let record = PhotoRecord(id: id, filename: filename, date: Date(), recipe: Recipe(), sourcePhotoID: request.sourcePhotoID, studioTemplateID: request.templateID, isAIGenerated: true)
            photos.insert(record, at: 0)
            try persist()
            await open(record)
            return selectedPhotoID == id
        } catch { self.error = error.localizedDescription; busy = false; return false }
    }
    private func add(data: Data, raw: Data? = nil, captured: AVDepthData? = nil, mattes: PortraitMattes? = nil, liveMovie: URL? = nil) async throws {
        let id = UUID()
        let filename = id.uuidString + ".photo"
        try data.write(to: documents.appendingPathComponent(filename), options: .atomic)
        if let liveMovie {
            defer { try? FileManager.default.removeItem(at: liveMovie) }
            try FileManager.default.copyItem(at: liveMovie, to: documents.appendingPathComponent(id.uuidString + ".mov"))
        }
        if let raw { try raw.write(to: documents.appendingPathComponent(id.uuidString + ".dng"), options: .atomic) }
        let record = PhotoRecord(id: id, filename: filename, date: Date(), recipe: Recipe())
        photos.insert(record, at: 0)
        try persist()
        await open(record, captured: captured, mattes: mattes)
    }

    func open(_ record: PhotoRecord, captured: AVDepthData? = nil, mattes: PortraitMattes? = nil) async {
        depthCancellation?.cancel(); depthCancellation = nil; analysisRunning = false; cancellingAnalysis = false
        busy = true
        generation += 1
        renderTask?.cancel()
        let ticket = generation
        do {
            let url = documents.appendingPathComponent(record.filename)
            let data = try Data(contentsOf: url)
            guard let decoded = CIImage(data: data, options: [.applyOrientationProperty: true]) else { throw LutelierError.message("Unsupported photo format.") }
            let image = decoded.transformed(by: CGAffineTransform(translationX: -decoded.extent.minX, y: -decoded.extent.minY))
            let base = try await render(image, recipe: Recipe(), look: .original, depth: nil, max: 1800)
            guard ticket == generation else { return }
            original = image; originalPreview = base; preview = base; renderedLookID = "original"
            selectedPhotoID = record.id; recipe = record.recipe; depth = nil; depthPreview = nil
            portraitPreview = nil; hairPreview = nil; matteStatus = "Analyze to find portrait edges"
            capturedMattes = mattes ?? PortraitMatteService.read(data)
            if capturedMattes.portrait == nil { capturedMattes.portrait = CIImage(contentsOf: documents.appendingPathComponent(record.id.uuidString + "-portrait.png")) }
            if capturedMattes.hair == nil { capturedMattes.hair = CIImage(contentsOf: documents.appendingPathComponent(record.id.uuidString + "-hair.png")) }
            hasDepth = false; hasSubject = false; history = []; future = []; thumbnails = [:]
            if let saved = CIImage(contentsOf: documents.appendingPathComponent(record.id.uuidString + "-depth.png")) { depth = DepthResult(subject: nil, depth: saved, explanation: "Saved depth"); hasDepth = true }
            depthStatus = "Analyze a portrait to unlock depth tools"
            var captureAnalyzed = false
            if let source = CGImageSourceCreateWithData(data as CFData, nil) {
                let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
                let orientation = CGImagePropertyOrientation(rawValue: (properties?[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1) ?? .up
                if let captured { await analyze(captured: captured.applyingExifOrientation(orientation), persistMask: false); captureAnalyzed = true }
                for type in [kCGImageAuxiliaryDataTypeDisparity, kCGImageAuxiliaryDataTypeDepth] where !captureAnalyzed {
                    if let dictionary = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, type) as? [AnyHashable: Any], let captured = try? AVDepthData(fromDictionaryRepresentation: dictionary) {
                        await analyze(captured: captured.applyingExifOrientation(orientation), persistMask: false); captureAnalyzed = true; break
                    }
                }
            }
            guard selectedPhotoID == record.id else { return }
            if let savedDepth = CIImage(contentsOf: documents.appendingPathComponent(record.id.uuidString + "-depth.png")) {
                if depth == nil { depth = DepthResult(subject: nil, depth: savedDepth, explanation: "Saved captured depth") }
                else { depth?.depth = savedDepth }
                hasDepth = true; depthStatus = "Saved depth • near and far planes available"
                let texture = try await renderDepthTexture(savedDepth)
                guard selectedPhotoID == record.id else { return }
                depthPreview = texture
            }
            if capturedMattes.available && !captureAnalyzed { await analyze(); captureAnalyzed = true }
            if let mask = CIImage(contentsOf: documents.appendingPathComponent(record.id.uuidString + "-mask.png")), !captureAnalyzed {
                if depth == nil { depth = DepthResult(subject: mask, depth: nil, explanation: "Saved portrait mask") }
                else { depth?.subject = mask }
                hasSubject = true
                matteStatus = "Saved portrait mask - on device"
                let texture = try await render(mask, recipe: Recipe(), look: .original, depth: nil, max: 1800)
                guard selectedPhotoID == record.id else { return }; portraitPreview = texture
                if !hasDepth { depthStatus = "Saved portrait mask • background blur available" }
            } else if !captureAnalyzed && (recipe.farBlur > 0 || recipe.nearBlur > 0 || recipe.light != .off) { await analyze() }
            busy = false
            scheduleRender()
        } catch { self.error = error.localizedDescription; busy = false }
    }

    private func recipe(for look: Look) -> Recipe {
        var next = recipe
        next.lookID = look.id
        next.grain = look.fx["grain"] ?? 0
        next.grainSize = look.fx["grain_size"] ?? 1
        next.grainColor = look.fx["grain_color"] ?? 0.2
        next.glow = look.fx["glow"] ?? 0
        next.halation = look.fx["halation"] ?? 0
        next.vignette = look.fx["vignette"] ?? 0
        return next
    }
    func select(_ look: Look) { let next = recipe(for: look); edit { $0 = next } }
    func prepareLook(_ look: Look) async throws -> (image: UIImage, recipe: Recipe) {
        guard let original else { throw LutelierError.message("Choose a photograph first.") }
        let next = recipe(for: look)
        let image = try await render(original, recipe: next, look: look, depth: depth, max: 1800)
        return (image, next)
    }
    func applyPreparedLook(image: UIImage, recipe next: Recipe) {
        history.append(recipe); if history.count > 100 { history.removeFirst() }; future = []
        generation += 1; renderTask?.cancel()
        recipe = next; preview = image; renderedLookID = next.lookID
        saveRecipe()
    }
    func edit(_ action: (inout Recipe) -> Void) {
        history.append(recipe); if history.count > 100 { history.removeFirst() }; future = []
        action(&recipe); scheduleRender(); saveRecipe()
    }
    func slider(_ key: WritableKeyPath<Recipe, Double>) -> Binding<Double> {
        Binding(get: { self.recipe[keyPath: key] }, set: { value in self.recipe[keyPath: key] = value; self.scheduleRender() })
    }
    func beginSlider() { history.append(recipe); future = [] }
    func endSlider() { saveRecipe() }
    func undo() { guard let previous = history.popLast() else { return }; future.append(recipe); recipe = previous; scheduleRender(); saveRecipe() }
    func redo() { guard let next = future.popLast() else { return }; history.append(recipe); recipe = next; scheduleRender(); saveRecipe() }
    func reset() { edit { $0 = Recipe() } }

    func scheduleRender() {
        generation += 1
        let ticket = generation
        renderTask?.cancel()
        guard let original else { return }
        let snapshot = recipe, look = currentLook, depth = depth
        renderTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(70))
                try Task.checkCancellation()
                let result = try await render(original, recipe: snapshot, look: look, depth: depth, max: 1800)
                guard !Task.isCancelled, ticket == generation else { return }
                preview = result; renderedLookID = snapshot.lookID
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
    private func render(_ image: CIImage, recipe: Recipe, look: Look, depth: DepthResult?, max: CGFloat?) async throws -> UIImage {
        let engine = engine
        return try await withCheckedThrowingContinuation { continuation in
            worker.async { continuation.resume(with: Result { try engine.render(image, recipe: recipe, look: look, depth: depth, maxDimension: max) }) }
        }
    }
    func thumbnail(_ look: Look) async {
        guard thumbnails[look.id] == nil, let original else { return }
        let photo = selectedPhotoID
        var settings = Recipe(); settings.lookID = look.id
        if let image = try? await render(original, recipe: settings, look: look, depth: nil, max: 160), selectedPhotoID == photo { thumbnails[look.id] = image }
    }

    func analyze(captured: AVDepthData? = nil, persistMask: Bool = true, regenerate: Bool = false, portraitOnly: Bool = false) async {
        guard let original else { return }
        guard !analysisRunning else { return }
        let cancellation = DepthCancellation(); depthCancellation = cancellation
        busy = true; analysisRunning = true; cancellingAnalysis = false
        depthStatus = portraitOnly ? "Finding portrait edges…" : "Analyzing with \(depthEngine.rawValue)…"
        defer { if depthCancellation === cancellation { if cancellation.isCancelled { depthStatus = "Cancelled • previous depth retained" }; busy = false; analysisRunning = false; cancellingAnalysis = false; depthCancellation = nil } }
        let photo = selectedPhotoID, service = depthService, selectedEngine = depthEngine
        do {
            let retainedDepth = regenerate ? nil : depth?.depth
            let mattes = capturedMattes
            var result: DepthResult = try await withCheckedThrowingContinuation { continuation in
                worker.async { continuation.resume(with: Result { try service.analyze(original, captured: captured, mattes: mattes, existingDepth: retainedDepth, engine: selectedEngine, requiresDepth: regenerate, portraitOnly: portraitOnly, progress: { status in
                    Task { @MainActor [weak self] in
                        guard let self, self.selectedPhotoID == photo, self.analysisRunning, self.depthCancellation === cancellation, !cancellation.isCancelled else { return }
                        self.depthStatus = status
                    }
                }, cancellation: cancellation) }) }
            }
            guard selectedPhotoID == photo, !cancellation.isCancelled else { return }
            if result.depth == nil, let retainedDepth { result.depth = retainedDepth; result.explanation = "Captured depth • portrait mask updated" }
            var nextPortrait: UIImage?, nextHair: UIImage?, nextDepth: UIImage?
            if let mask = result.subject { nextPortrait = try await render(mask, recipe: Recipe(), look: .original, depth: nil, max: 1800) }
            try cancellation.check()
            if let hair = result.hair { nextHair = try await render(hair, recipe: Recipe(), look: .original, depth: nil, max: 1800) }
            try cancellation.check()
            if let map = result.depth { nextDepth = try await renderDepthTexture(map) }
            try cancellation.check()
            guard selectedPhotoID == photo else { return }
            // Commit all analysis state together only after cancellable work finishes.
            analysisRunning = false
            depth = result; hasDepth = result.depth != nil; hasSubject = result.subject != nil; depthStatus = result.explanation
            matteStatus = result.matteExplanation
            portraitPreview = nextPortrait; hairPreview = nextHair; depthPreview = nextDepth
            if let hair = result.hair { try await saveMask(hair, photo: photo, suffix: "-hair", format: .RGBA16) }
            if let portrait = result.portrait { try await saveMask(portrait, photo: photo, suffix: "-portrait", format: .RGBA16) }
            if persistMask, let mask = result.subject { try await saveMask(mask, photo: photo) }
            if let map = result.depth { try await saveMask(map, photo: photo, suffix: "-depth", format: .RGBA16) }
            guard selectedPhotoID == photo else { return }
            scheduleRender()
        } catch is CancellationError {
            if selectedPhotoID == photo { depthStatus = "Analysis cancelled • previous depth retained" }
        } catch {
            guard selectedPhotoID == photo, !cancellation.isCancelled else { return }
            self.error = error.localizedDescription
            depthStatus = "\(selectedEngine.rawValue) failed: \(error.localizedDescription)"
        }
    }
    private func renderDepthTexture(_ map: CIImage) async throws -> UIImage {
        // Older saved maps store their scalar in red only; inspect all maps as gray.
        let gray = map.applyingFilter("CIColorMatrix", parameters: [
            "inputGVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 1, y: 0, z: 0, w: 0)])
        return try await render(gray, recipe: Recipe(), look: .original, depth: nil, max: 1800)
    }

    func refine(normalized region: CGRect) async {
        guard let original, let existing = depth?.depth else { return }
        guard !analysisRunning else { return }
        let cancellation = DepthCancellation(); depthCancellation = cancellation
        busy = true; analysisRunning = true; cancellingAnalysis = false
        defer { if depthCancellation === cancellation { if cancellation.isCancelled { depthStatus = "Cancelled • previous depth retained" }; busy = false; analysisRunning = false; cancellingAnalysis = false; depthCancellation = nil } }
        depthStatus = "Refining selected area…"
        let photo = selectedPhotoID, service = depthService, method = depthRefinementMethod, selectedEngine = depthEngine
        let crop = CGRect(x: region.minX * original.extent.width, y: (1 - region.maxY) * original.extent.height, width: region.width * original.extent.width, height: region.height * original.extent.height)
        do {
            let result: DepthRefinementResult = try await withCheckedThrowingContinuation { continuation in
                worker.async { continuation.resume(with: Result { try service.refineDepth(original, region: crop, existing: existing, method: method, engine: selectedEngine, cancellation: cancellation) }) }
            }
            guard selectedPhotoID == photo, !cancellation.isCancelled else { return }
            let mask = result.image
            let texture = try await renderDepthTexture(mask)
            try cancellation.check()
            guard selectedPhotoID == photo else { return }
            analysisRunning = false
            depth?.depth = mask
            depthStatus = method == .contextual ? "On-device context crop refined • edges feathered" : "On-device detail fusion • \(result.acceptedTiles)/4 tiles accepted • \(result.rejectedTiles) rejected • experimental"
            depthPreview = texture
            try await saveMask(mask, photo: photo, suffix: "-depth", format: .RGBA16)
            scheduleRender()
        } catch is CancellationError {
            if selectedPhotoID == photo { depthStatus = "Refinement cancelled • previous depth retained" }
        } catch { if selectedPhotoID == photo, !cancellation.isCancelled { self.error = error.localizedDescription } }
    }

    private func saveMask(_ image: CIImage, photo: UUID?, suffix: String = "-mask", format: CIFormat = .RGBA8) async throws {
        guard let photo else { return }
        let engine = engine, url = documents.appendingPathComponent(photo.uuidString + suffix + ".png")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            worker.async {
                continuation.resume(with: Result {
                    guard let data = engine.context.pngRepresentation(of: image, format: format, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, options: [:]) else { throw LutelierError.message("Could not save the portrait analysis.") }
                    try data.write(to: url, options: .atomic)
                })
            }
        }
    }

    var hasLivePhoto: Bool { selectedPhotoID.map { FileManager.default.fileExists(atPath: documents.appendingPathComponent($0.uuidString + ".mov").path) } ?? false }
    func exportLiveOriginal() async {
        guard let id = selectedPhotoID, let record = photos.first(where: { $0.id == id }) else { return }
        do {
            let permission = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard permission == .authorized || permission == .limited else { throw LutelierError.message("Allow Lutelier to add photos in Settings.") }
            let still = documents.appendingPathComponent(record.filename), movie = documents.appendingPathComponent(id.uuidString + ".mov")
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, fileURL: still, options: nil)
                request.addResource(with: .pairedVideo, fileURL: movie, options: nil)
            }
            message = "Live Photo original saved to Photos."
        } catch { self.error = error.localizedDescription }
    }

    var hasRaw: Bool {
        guard let selectedPhotoID else { return false }
        return FileManager.default.fileExists(atPath: documents.appendingPathComponent(selectedPhotoID.uuidString + ".dng").path)
    }
    func exportRaw() async {
        guard let selectedPhotoID, hasRaw else { return }
        do {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else { throw LutelierError.message("Enable permission to add photographs in Settings → Lutelier → Photos.") }
            let url = documents.appendingPathComponent(selectedPhotoID.uuidString + ".dng")
            try await PHPhotoLibrary.shared().performChanges { PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: url, options: nil) }
            message = "RAW original saved to Photos."
        } catch { self.error = error.localizedDescription }
    }

    func askAssistant() async {
        guard !assistantPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        assistantBusy = true
        defer { assistantBusy = false }
        do {
            let suggestion = try await AssistantService.suggest(assistantPrompt, context: "Look: \(currentLook.name). \(depthStatus). Current exposure: \(recipe.exposure).")
            edit {
                $0.exposure = suggestion.exposure.isFinite ? min(max(suggestion.exposure, -2), 2) : 0
                $0.temperature = suggestion.temperature.isFinite ? min(max(suggestion.temperature, 3000), 9000) : 6500
                $0.grain = suggestion.grain.isFinite ? min(max(suggestion.grain, 0), 1) : 0
                if hasSubject || hasDepth { $0.farBlur = suggestion.backgroundBlur.isFinite ? min(max(suggestion.backgroundBlur, 0), 1) : 0 }
            }
            message = suggestion.explanation
        } catch { self.error = error.localizedDescription }
    }

    func export() async {
        guard let original else { return }
        busy = true
        defer { busy = false }
        do {
            let rendered = try await render(original, recipe: recipe, look: currentLook, depth: depth, max: nil)
            guard let data = rendered.jpegData(compressionQuality: 0.97) else { throw LutelierError.message("Could not encode the export.") }
            let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard authorization == .authorized || authorization == .limited else { throw LutelierError.message("Enable permission to add photographs in Settings → Lutelier → Photos.") }
            try await PHPhotoLibrary.shared().performChanges { PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil) }
            message = "Full-resolution edit saved to Photos. Your original is preserved in Lutelier."
        } catch { self.error = error.localizedDescription }
    }

    func importCube(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            var size = 0, floats: [Float] = []
            for line in text.components(separatedBy: .newlines) {
                let parts = line.split(whereSeparator: { $0.isWhitespace })
                guard let first = parts.first, !first.hasPrefix("#") else { continue }
                if first == "LUT_3D_SIZE", parts.count == 2 { size = Int(parts[1]) ?? 0 }
                else if first == "LUT_1D_SIZE" { throw LutelierError.message("Import a 3D .cube LUT; 1D LUTs are not supported.") }
                else if first == "DOMAIN_MIN" || first == "DOMAIN_MAX" {
                    let expected: Float = first == "DOMAIN_MIN" ? 0 : 1
                    guard parts.dropFirst().count == 3, parts.dropFirst().allSatisfy({ Float($0) == expected }) else { throw LutelierError.message("This LUT uses a custom input domain. Normalize it to 0–1 before import.") }
                } else if let r = Float(first), parts.count == 3, let g = Float(parts[1]), let b = Float(parts[2]) {
                    guard r.isFinite, g.isFinite, b.isFinite else { throw LutelierError.message("The LUT contains invalid color values.") }
                    floats += [min(max(r, 0), 1), min(max(g, 0), 1), min(max(b, 0), 1), 1]
                }
            }
            guard (2...65).contains(size), floats.count == size * size * size * 4 else { throw LutelierError.message("Invalid LUT. Supported cube dimensions are 2–65.") }
            let id = UUID().uuidString, file = id + ".rgba"
            let directory = documents.appendingPathComponent("Looks")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try floats.withUnsafeBytes { Data($0) }.write(to: directory.appendingPathComponent(file), options: .atomic)
            let look = Look(id: id, name: url.deletingPathExtension().lastPathComponent, category: "Imported", description: "Your imported 3D LUT", file: file, dimension: size, fx: [:])
            looks.append(look)
            try JSONEncoder().encode(looks.filter { $0.category == "Imported" }).write(to: documents.appendingPathComponent("imported-looks.json"), options: .atomic)
            select(look)
        } catch { self.error = error.localizedDescription }
    }

    private func saveRecipe() {
        guard let index = photos.firstIndex(where: { $0.id == selectedPhotoID }) else { return }
        photos[index].recipe = recipe
        do { try persist() } catch { self.error = error.localizedDescription }
    }
    private func persist() throws { try JSONEncoder().encode(photos).write(to: documents.appendingPathComponent("library.json"), options: .atomic) }
    func libraryThumbnail(_ photo: PhotoRecord) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(documents.appendingPathComponent(photo.filename) as CFURL, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 320, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
