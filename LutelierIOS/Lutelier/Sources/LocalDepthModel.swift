import CoreML
import Vision
import CoreImage

/// Relative disparity: white is nearer. This is not a metric-distance model.
final class LocalDepthModel {
    private var cached: VNCoreMLModel?
    private let context = CIContext()
    func estimate(_ image: CIImage) throws -> CIImage {
        if cached == nil {
            let compiled = Bundle.main.url(forResource: "DepthAnythingV2SmallF16", withExtension: "mlmodelc")
            let package = Bundle.main.url(forResource: "DepthAnythingV2SmallF16", withExtension: "mlpackage", subdirectory: "Models")
            guard let url = compiled ?? package else { throw LutelierError.message("The local depth model is missing from this build.") }
            let configuration = MLModelConfiguration(); configuration.computeUnits = .all
            let modelURL = url.pathExtension == "mlmodelc" ? url : try MLModel.compileModel(at: url)
            cached = try VNCoreMLModel(for: MLModel(contentsOf: modelURL, configuration: configuration))
        }
        let request = VNCoreMLRequest(model: cached!); request.imageCropAndScaleOption = .scaleFill
        try VNImageRequestHandler(ciImage: image, options: [:]).perform([request])
        let map: CIImage
        if let output = request.results?.compactMap({ $0 as? VNPixelBufferObservation }).first {
            map = CIImage(cvPixelBuffer: output.pixelBuffer)
        } else if let array = request.results?.compactMap({ ($0 as? VNCoreMLFeatureValueObservation)?.featureValue.multiArrayValue }).first {
            let shape = array.shape.map { $0.intValue }
            guard shape.count >= 2 else { throw LutelierError.message("Unexpected depth-model output dimensions.") }
            let w = shape[shape.count - 1], h = shape[shape.count - 2]
            var pixels = [Float](repeating: 0, count: w * h)
            for y in 0..<h { for x in 0..<w {
                var index = [NSNumber](repeating: 0, count: shape.count)
                index[shape.count - 2] = NSNumber(value: y); index[shape.count - 1] = NSNumber(value: x)
                pixels[(h - 1 - y) * w + x] = array[index].floatValue
            } }
            map = Self.image(pixels, width: w, height: h)
        } else { throw LutelierError.message("The local model did not return a depth texture.") }
        let w = Int(map.extent.width), h = Int(map.extent.height)
        var values = samples(map, width: w, height: h)
        let ordered = values.filter { $0.isFinite }.sorted()
        guard let first = ordered.first, let last = ordered.last, last > first else { throw LutelierError.message("This photograph produced an unreliable flat depth map.") }
        let lo = ordered[ordered.count / 100], hi = ordered[min(ordered.count - 1, ordered.count * 99 / 100)]
        values = values.map { $0.isFinite ? min(1, max(0, ($0 - lo) / max(hi - lo, 0.00001))) : 0 }
        return Self.image(values, width: w, height: h).transformed(by: CGAffineTransform(scaleX: image.extent.width / CGFloat(w), y: image.extent.height / CGFloat(h)))
            .transformed(by: CGAffineTransform(translationX: image.extent.minX, y: image.extent.minY)).cropped(to: image.extent)
    }
    func refine(_ image: CIImage, region: CGRect, existing: CIImage, method: DepthRefinementMethod) throws -> DepthRefinementResult {
        let selection = region.intersection(image.extent)
        guard selection.width >= 48, selection.height >= 48 else { throw LutelierError.message("Select a larger area for depth refinement.") }
        if method == .overlapping {
            guard ProcessInfo.processInfo.thermalState != .serious, ProcessInfo.processInfo.thermalState != .critical else {
                throw LutelierError.message("Let your iPhone cool down, or choose Context crop for fewer depth passes.")
            }
        }
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
                let map = try estimate(image.cropped(to: rect))
                let fitted = map.transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
                    .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
                var values = [Float](repeating: 0, count: w * h)
                values.withUnsafeMutableBytes { context.render(fitted, toBitmap: $0.baseAddress!, rowBytes: w * 4, bounds: bounds, format: .Rf, colorSpace: CGColorSpaceCreateDeviceGray()) }
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
                guard ProcessInfo.processInfo.thermalState != .critical else { throw LutelierError.message("Depth refinement paused because your iPhone is too hot. The previous depth map is unchanged.") }
                do { let patch = try infer(tile); try accumulator.add(local: patch, support: grid(tile)); accepted += 1 }
                catch { rejected += 1 } // Consistency rejection retains the contextual anchor.
            }
            guard ProcessInfo.processInfo.thermalState != .critical else { throw LutelierError.message("Your iPhone became too hot. The previous depth map is unchanged.") }
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
        values.withUnsafeMutableBytes { context.render(fitted, toBitmap: $0.baseAddress!, rowBytes: width * 4, bounds: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)), format: .Rf, colorSpace: CGColorSpaceCreateDeviceGray()) }
        return values
    }
    private static func image(_ values: [Float], width: Int, height: Int) -> CIImage {
        let data = values.withUnsafeBytes { Data($0) }
        return CIImage(bitmapData: data, bytesPerRow: width * 4, size: CGSize(width: CGFloat(width), height: CGFloat(height)), format: .Rf, colorSpace: CGColorSpaceCreateDeviceGray())
    }
}
