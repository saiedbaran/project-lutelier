import CoreML
import Vision
import CoreImage

enum DepthEngine: String, CaseIterable, Identifiable, Sendable {
    case anything = "Depth Anything V2"
    case anything3 = "Depth Anything 3"
    case pro = "Depth Pro"
    var id: String { rawValue }
    var modelName: String {
        switch self {
        case .anything: "DepthAnythingV2SmallF16"
        case .anything3: "DepthAnythingV3_small_504"
        case .pro: "DepthProEncoder"
        }
    }
    var modelURL: URL? {
        Bundle.main.url(forResource: modelName, withExtension: "mlmodelc", subdirectory: "Models")
            ?? Bundle.main.url(forResource: modelName, withExtension: "mlmodelc")
            ?? Bundle.main.url(forResource: modelName, withExtension: "mlpackage", subdirectory: "Models")
    }
    var isInstalled: Bool {
        modelURL != nil && (self != .pro || Bundle.main.url(forResource: "DepthProDecoder", withExtension: "mlmodelc", subdirectory: "Models") != nil)
    }
}

/// Relative disparity: white is nearer. This is not a metric-distance model.
final class DepthCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func check() throws { if isCancelled { throw CancellationError() } }
}

final class LocalDepthModel {
    private var cached: VNCoreMLModel?
    private var cachedEngine: DepthEngine?
    private let context = CIContext(options: [.workingColorSpace: NSNull()])
    func estimate(_ image: CIImage, engine: DepthEngine = .anything, progress: ((String) -> Void)? = nil, cancellation: DepthCancellation? = nil) throws -> CIImage {
        try cancellation?.check()
        let map: CIImage
        if engine == .pro {
            cached = nil; cachedEngine = nil
            map = try tiledDepthPro(image, progress: progress, cancellation: cancellation)
        } else {
            if cachedEngine != engine {
                cached = nil; cachedEngine = nil
            }
            if cached == nil {
                progress?("Preparing \(engine.rawValue)… First use may take several minutes.")
                guard let url = engine.modelURL else { throw LutelierError.message("\(engine.rawValue) is missing from this build.") }
                let configuration = MLModelConfiguration()
                configuration.computeUnits = .all
                let modelURL = url.pathExtension == "mlmodelc" ? url : try MLModel.compileModel(at: url)
                cached = try VNCoreMLModel(for: MLModel(contentsOf: modelURL, configuration: configuration))
                cachedEngine = engine
            }
            progress?("Estimating scene depth with \(engine.rawValue)…")
            let request = VNCoreMLRequest(model: cached!); request.imageCropAndScaleOption = .scaleFill
            try cancellation?.check()
            try VNImageRequestHandler(ciImage: image, options: [:]).perform([request])
            try cancellation?.check()
            if let output = request.results?.compactMap({ $0 as? VNPixelBufferObservation }).first {
                map = CIImage(cvPixelBuffer: output.pixelBuffer, options: [.colorSpace: NSNull()])
            } else if let array = request.results?.compactMap({ $0 as? VNCoreMLFeatureValueObservation }).first(where: { engine != .anything3 || $0.featureName == "depth" })?.featureValue.multiArrayValue {
                let shape = array.shape.map { $0.intValue }
                guard shape.count >= 2 else { throw LutelierError.message("Unexpected depth-model output dimensions.") }
                let w = shape[shape.count - 1], h = shape[shape.count - 2]
                var pixels = [Float](repeating: 0, count: w * h)
                for y in 0..<h { for x in 0..<w {
                    var index = [NSNumber](repeating: 0, count: shape.count)
                    index[shape.count - 2] = NSNumber(value: y); index[shape.count - 1] = NSNumber(value: x)
                    let value = array[index].floatValue
                    pixels[y * w + x] = engine == .anything3 ? 1 / max(value, 0.000001) : value
                } }
                map = Self.image(pixels, width: w, height: h)
            } else { throw LutelierError.message("The local model did not return a depth texture.") }
        }
        try cancellation?.check()
        progress?("Normalizing scene depth…")
        let w = Int(map.extent.width), h = Int(map.extent.height)
        var values = samples(map, width: w, height: h)
        let ordered = values.filter { $0.isFinite }.sorted()
        guard let first = ordered.first, let last = ordered.last, last > first else { throw LutelierError.message("This photograph produced an unreliable flat depth map.") }
        let lo = ordered[ordered.count / 100], hi = ordered[min(ordered.count - 1, ordered.count * 99 / 100)]
        values = values.map { $0.isFinite ? min(1, max(0, ($0 - lo) / max(hi - lo, 0.00001))) : 0 }
        return Self.image(values, width: w, height: h).transformed(by: CGAffineTransform(scaleX: image.extent.width / CGFloat(w), y: image.extent.height / CGFloat(h)))
            .transformed(by: CGAffineTransform(translationX: image.extent.minX, y: image.extent.minY)).cropped(to: image.extent)
    }
    /// The original decoder expands to a 600 MB activation. Decode overlapping
    /// latent crops sequentially, retaining the global encoder's full-image context.
    private func tiledDepthPro(_ image: CIImage, progress: ((String) -> Void)?, cancellation: DepthCancellation?) throws -> CIImage {
        try cancellation?.check()
        let names = ["input_875_cast_fp16", "input_883_cast_fp16", "input_957_cast_fp16"]
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndGPU
        configuration.allowLowPrecisionAccumulationOnGPU = true
        progress?("Depth Pro: preparing encoder (first use can take several minutes)…")
        let features: [MLMultiArray] = try autoreleasepool {
            guard let url = DepthEngine.pro.modelURL else { throw LutelierError.message("Depth Pro encoder is missing.") }
            let model = try MLModel(contentsOf: url, configuration: configuration)
            progress?("Depth Pro: encoding the photograph…")
            var buffer: CVPixelBuffer?
            let status = CVPixelBufferCreate(kCFAllocatorDefault, 1536, 1536, kCVPixelFormatType_32BGRA,
                [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
            guard status == kCVReturnSuccess, let buffer else { throw LutelierError.message("Not enough memory for Depth Pro's input.") }
            let fitted = PortraitMatteService.fit(image, to: CGRect(x: 0, y: 0, width: 1536, height: 1536))
            CIContext().render(fitted, to: buffer, bounds: fitted.extent, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            try cancellation?.check()
            let output = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: buffer)]))
            return try names.enumerated().map { index, name in
                guard let array = output.featureValue(for: name)?.multiArrayValue else { throw LutelierError.message("Depth Pro did not return its image features.") }
                let side = index == 2 ? 192 : 96
                guard array.shape.map(\.intValue) == [1, 256, side, side] else { throw LutelierError.message("Depth Pro returned incompatible image features.") }
                return array
            }
        }
        // Release the encoder before loading the much smaller convolution decoder.
        guard let url = Bundle.main.url(forResource: "DepthProDecoder", withExtension: "mlmodelc", subdirectory: "Models") else {
            throw LutelierError.message("Depth Pro tile decoder is missing.")
        }
        try cancellation?.check()
        let decoder = try MLModel(contentsOf: url, configuration: configuration)
        var values = [Float](repeating: 0, count: 1536 * 1536)
        for row in 0..<4 { for column in 0..<4 {
            try cancellation?.check()
            progress?("Depth Pro: detail tile \(row * 4 + column + 1) of 16…")
            try autoreleasepool {
                let originX = min(64, max(0, column * 24 - 4)), originY = min(64, max(0, row * 24 - 4))
                var inputs: [String: MLFeatureValue] = [:]
                for (index, name) in names.enumerated() {
                    let scale = index == 2 ? 2 : 1
                    inputs[name] = MLFeatureValue(multiArray: try Self.featureCrop(features[index], x: originX * scale, y: originY * scale, size: 32 * scale))
                }
                let prediction = try decoder.prediction(from: MLDictionaryFeatureProvider(dictionary: inputs))
                guard let output = prediction.featureValue(for: "canonical_inverse_depth_cast_fp16")?.multiArrayValue else {
                    throw LutelierError.message("Depth Pro did not return a decoded tile.")
                }
                guard output.shape.map(\.intValue) == [1, 1, 512, 512] else { throw LutelierError.message("Depth Pro returned an incompatible detail tile.") }
                let offsetX = (column * 24 - originX) * 16, offsetY = (row * 24 - originY) * 16
                let strides = output.strides.map(\.intValue)
                for y in 0..<384 { for x in 0..<384 {
                    let offset = (offsetY + y) * strides[2] + (offsetX + x) * strides[3]
                    let value: Float
                    if output.dataType == .float16 { value = Float(output.dataPointer.assumingMemoryBound(to: Float16.self)[offset]) }
                    else if output.dataType == .float32 { value = output.dataPointer.assumingMemoryBound(to: Float.self)[offset] }
                    else { value = output[[0, 0, NSNumber(value: offsetY + y), NSNumber(value: offsetX + x)]].floatValue }
                    values[(row * 384 + y) * 1536 + column * 384 + x] = value
                } }
            }
        } }
        return Self.image(values, width: 1536, height: 1536)
    }

    private static func featureCrop(_ source: MLMultiArray, x: Int, y: Int, size: Int) throws -> MLMultiArray {
        let channels = source.shape[1].intValue
        let crop = try MLMultiArray(shape: [1, NSNumber(value: channels), NSNumber(value: size), NSNumber(value: size)], dataType: source.dataType)
        let inputStrides = source.strides.map(\.intValue), outputStrides = crop.strides.map(\.intValue)
        let bytes = source.dataType == .float16 ? 2 : source.dataType == .double ? 8 : 4
        for channel in 0..<channels { for row in 0..<size {
            if inputStrides[3] == 1 && outputStrides[3] == 1 {
                let inputOffset = channel * inputStrides[1] + (y + row) * inputStrides[2] + x
                let outputOffset = channel * outputStrides[1] + row * outputStrides[2]
                memcpy(crop.dataPointer.advanced(by: outputOffset * bytes), source.dataPointer.advanced(by: inputOffset * bytes), size * bytes)
            } else {
                for column in 0..<size {
                    crop[[0, NSNumber(value: channel), NSNumber(value: row), NSNumber(value: column)]] = source[[0, NSNumber(value: channel), NSNumber(value: y + row), NSNumber(value: x + column)]]
                }
            }
        } }
        return crop
    }

    func refine(_ image: CIImage, region: CGRect, existing: CIImage, method: DepthRefinementMethod, engine: DepthEngine = .anything, cancellation: DepthCancellation? = nil) throws -> DepthRefinementResult {
        try cancellation?.check()
        let selection = region.intersection(image.extent)
        guard selection.width >= 48, selection.height >= 48 else { throw LutelierError.message("Select a larger area for depth refinement.") }
        let crop = selection.insetBy(dx: -selection.width * 0.2, dy: -selection.height * 0.2).intersection(image.extent)
        // Spend the bounded working grid on the selected ROI, not the entire 48MP photograph.
        let scale = min(1, 2048 / max(crop.width, crop.height))
        let w = max(1, Int(crop.width * scale)), h = max(1, Int(crop.height * scale))
        let sx = CGFloat(w) / crop.width, sy = CGFloat(h) / crop.height
        let bounds = CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h))
        func grid(_ rect: CGRect) -> CGRect {
            CGRect(x: (rect.minX - crop.minX) * sx, y: (rect.minY - crop.minY) * sy, width: rect.width * sx, height: rect.height * sy)
        }
        func infer(_ rect: CGRect) throws -> [Float] {
            try autoreleasepool {
                let map = try estimate(image.cropped(to: rect), engine: engine, cancellation: cancellation)
                let fitted = map.transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
                    .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
                var values = [Float](repeating: 0, count: w * h)
                values.withUnsafeMutableBytes { context.render(fitted, toBitmap: $0.baseAddress!, rowBytes: w * 4, bounds: bounds, format: .Rf, colorSpace: nil) }
                return values
            }
        }
        let global = samples(existing.cropped(to: crop), width: w, height: h)
        let coarse = try infer(crop)
        let rect = grid(selection)
        let fused: [Float]
        var accepted = 0, rejected = 0
        if method == .contextual {
            fused = try DepthPatchFusion.merge(global: global, local: coarse, width: w, height: h, selection: rect, support: bounds)
        } else {
            let alignment = try DepthPatchFusion.alignment(global: global, local: coarse, width: w, height: h, support: bounds)
            let anchor = coarse.map { min(1, max(0, alignment.value($0))) }
            var accumulator = DepthPatchFusion.Accumulator(anchor: anchor, width: w, height: h)
            // Sequential inference keeps one model instance and one tile buffer in flight.
            for tile in DepthPatchFusion.tiles(in: crop) {
            try cancellation?.check()
                do { let patch = try infer(tile); try accumulator.add(local: patch, support: grid(tile)); accepted += 1 }
                catch is CancellationError { throw CancellationError() }
                catch { rejected += 1 } // Consistency rejection retains the contextual anchor.
            }
            try cancellation?.check()
            guard accepted > 0 else { throw LutelierError.message("The detail tiles could not be aligned reliably. The previous depth is unchanged; try Context crop or a wider selection.") }
            fused = accumulator.finish(original: global, selection: rect)
        }
        let refined = Self.image(fused, width: w, height: h)
            .transformed(by: CGAffineTransform(scaleX: crop.width / CGFloat(w), y: crop.height / CGFloat(h)))
            .transformed(by: CGAffineTransform(translationX: crop.minX, y: crop.minY)).cropped(to: image.extent)
        // Full-resolution depth outside the box is copied from the prior map, never resized.
        let mask = CIImage(color: .white).cropped(to: selection)
            .composited(over: CIImage(color: .black).cropped(to: image.extent))
        let result = refined.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: existing, kCIInputMaskImageKey: mask]).cropped(to: image.extent)
        return DepthRefinementResult(image: result, acceptedTiles: accepted, rejectedTiles: rejected)
    }
    private func samples(_ image: CIImage, width: Int, height: Int) -> [Float] {
        let fitted = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY)).transformed(by: CGAffineTransform(scaleX: CGFloat(width) / image.extent.width, y: CGFloat(height) / image.extent.height))
        var values = [Float](repeating: 0, count: width * height)
        values.withUnsafeMutableBytes { context.render(fitted, toBitmap: $0.baseAddress!, rowBytes: width * 4, bounds: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)), format: .Rf, colorSpace: nil) }
        return values
    }
    private static func image(_ values: [Float], width: Int, height: Int) -> CIImage {
        let data = values.withUnsafeBytes { Data($0) }
        return CIImage(bitmapData: data, bytesPerRow: width * 4, size: CGSize(width: CGFloat(width), height: CGFloat(height)), format: .Rf, colorSpace: nil)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputGVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 1, y: 0, z: 0, w: 0)])
    }
}
