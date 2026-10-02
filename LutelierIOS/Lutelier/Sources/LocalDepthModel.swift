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
    func refine(_ image: CIImage, region: CGRect, existing: CIImage) throws -> CIImage {
        let selection = region.intersection(image.extent)
        guard selection.width >= 48, selection.height >= 48 else { throw LutelierError.message("Select a larger area for depth refinement.") }
        // Context around the box gives the model a stable reference for crop-scale alignment.
        let crop = selection.insetBy(dx: -selection.width * 0.2, dy: -selection.height * 0.2).intersection(image.extent)
        let local = try estimate(image.cropped(to: crop))
        let maxSide: CGFloat = 2048, scale = min(1, maxSide / max(image.extent.width, image.extent.height))
        let w = Int(image.extent.width * scale), h = Int(image.extent.height * scale)
        let global = samples(existing, width: w, height: h)
        let alignedLocal = local.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY)).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        var patch = [Float](repeating: 0, count: w * h)
        patch.withUnsafeMutableBytes { context.render(alignedLocal, toBitmap: $0.baseAddress!, rowBytes: w * 4, bounds: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)), format: .Rf, colorSpace: CGColorSpaceCreateDeviceGray()) }
        let rect = CGRect(x: (selection.minX - image.extent.minX) * scale, y: (selection.minY - image.extent.minY) * scale, width: selection.width * scale, height: selection.height * scale)
        let support = CGRect(x: (crop.minX - image.extent.minX) * scale, y: (crop.minY - image.extent.minY) * scale, width: crop.width * scale, height: crop.height * scale)
        let fused = try DepthPatchFusion.merge(global: global, local: patch, width: w, height: h, selection: rect, support: support)
        let refined = Self.image(fused, width: w, height: h).transformed(by: CGAffineTransform(scaleX: image.extent.width / CGFloat(w), y: image.extent.height / CGFloat(h)))
            .transformed(by: CGAffineTransform(translationX: image.extent.minX, y: image.extent.minY)).cropped(to: image.extent)
        // Preserve the original full-resolution texture outside the box, including fine edges.
        let mask = CIImage(color: .white).cropped(to: selection)
            .composited(over: CIImage(color: .black).cropped(to: image.extent))
        return refined.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: existing, kCIInputMaskImageKey: mask]).cropped(to: image.extent)
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

enum DepthPatchFusion {
    static func merge(global: [Float], local: [Float], width: Int, height: Int, selection: CGRect, support: CGRect) throws -> [Float] {
        guard global.count == width * height, local.count == global.count else { throw LutelierError.message("Depth texture sizes do not match.") }
        var pairs: [(Double, Double)] = []
        for y in stride(from: max(0, Int(support.minY)), to: min(height, Int(support.maxY)), by: 3) {
            for x in stride(from: max(0, Int(support.minX)), to: min(width, Int(support.maxX)), by: 3) {
                let a = Double(local[y * width + x]), b = Double(global[y * width + x])
                if a.isFinite && b.isFinite { pairs.append((a,b)) }
            }
        }
        guard pairs.count >= 16 else { throw LutelierError.message("Not enough context to align this depth patch.") }
        var scale = 1.0, bias = 0.0
        for pass in 0..<2 {
            let n = Double(pairs.count), sx = pairs.reduce(0) { $0 + $1.0 }, sy = pairs.reduce(0) { $0 + $1.1 }
            let variance = pairs.reduce(0) { $0 + $1.0 * $1.0 } - sx * sx / n
            guard variance > 0.00001 else { throw LutelierError.message("This crop is too flat to align safely. Include nearby objects or edges.") }
            scale = (pairs.reduce(0) { $0 + $1.0 * $1.1 } - sx * sy / n) / variance; bias = (sy - scale * sx) / n
            guard scale > 0.05 && scale < 20 else { throw LutelierError.message("The crop conflicts with the existing depth. Try a wider box.") }
            if pass == 0 {
                let residuals = pairs.map { abs(scale * $0.0 + bias - $0.1) }.sorted(), threshold = max(0.005, residuals[residuals.count * 8 / 10])
                pairs = pairs.filter { abs(scale * $0.0 + bias - $0.1) <= threshold }
            }
        }
        var result = global
        let feather = max(2, min(selection.width, selection.height) * 0.12)
        for y in max(0, Int(selection.minY))..<min(height, Int(selection.maxY)) { for x in max(0, Int(selection.minX))..<min(width, Int(selection.maxX)) {
            let distance = min(CGFloat(x) - selection.minX, selection.maxX - CGFloat(x), CGFloat(y) - selection.minY, selection.maxY - CGFloat(y))
            let t = Float(min(1, max(0, distance / feather))), weight = t * t * (3 - 2 * t), i = y * width + x
            let value = Float(scale * Double(local[i]) + bias)
            if value.isFinite { result[i] = global[i] * (1 - weight) + min(1, max(0, value)) * weight }
        } }
        return result
    }
}
