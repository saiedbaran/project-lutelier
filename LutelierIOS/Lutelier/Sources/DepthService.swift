import Vision
import CoreImage
import AVFoundation
import ImageIO

struct DepthResult {
    var subject: CIImage?
    var depth: CIImage?
    var explanation: String
    var portrait: CIImage? = nil
    var hair: CIImage? = nil
    var matteExplanation: String = "Portrait edges not analyzed"
}

/// Vision mattes identify people; they are never presented as metric depth.
final class DepthService {
    private let localModel = LocalDepthModel()
    func analyze(_ image: CIImage, captured: AVDepthData? = nil, mattes: PortraitMattes = PortraitMattes(), existingDepth: CIImage? = nil, engine: DepthEngine = .anything, requiresDepth: Bool = false, portraitOnly: Bool = false, progress: ((String) -> Void)? = nil, cancellation: DepthCancellation? = nil) throws -> DepthResult {
        try cancellation?.check()
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        // Captured portrait coverage has finer edges than a new whole-photo segmentation.
        if mattes.portrait == nil { try VNImageRequestHandler(ciImage: image, options: [:]).perform([request]) }
        let fallback = request.results?.first.flatMap { observation -> CIImage? in
            let mask = fit(CIImage(cvPixelBuffer: observation.pixelBuffer, options: [.colorSpace: NSNull()]), to: image.extent)
            return hasForeground(mask) ? mask : nil
        }
        let portrait = mattes.portrait.map { fit($0, to: image.extent) }
        let hair = mattes.hair.map { fit($0, to: image.extent) }
        let mask = PortraitMatteService.subject(portrait: portrait, hair: hair, fallback: fallback, extent: image.extent)
        var depth: CIImage?, explanation: String
        do {
            if portraitOnly {
                depth = existingDepth
                explanation = existingDepth != nil ? "Scene depth retained • portrait updated" : mask != nil ? "Portrait blur ready • analyze for scene depth" : "No person found in this photograph"
            } else {
                depth = try existingDepth ?? captured.map { normalize($0, extent: image.extent) } ?? localModel.estimate(image, engine: engine, progress: progress, cancellation: cancellation)
                explanation = captured != nil || existingDepth != nil ? "Retained/captured depth • white is near" : "\(engine.rawValue) • on-device relative depth • white is near"
            }
        } catch is CancellationError { throw CancellationError() } catch {
            guard !requiresDepth, mask != nil else { throw error }
            explanation = "\(engine.rawValue) failed: \(error.localizedDescription) • portrait blur remains available"
        }
        try cancellation?.check()
        let detail = portrait != nil ? hair != nil ? "Apple portrait + hair mattes • on device" : "Apple portrait matte • on device"
            : hair != nil ? "Apple hair matte + Vision person mask • on device" : mask != nil ? "Vision accurate person mask • no captured hair matte" : "No portrait matte available"
        return DepthResult(subject: mask, depth: depth, explanation: explanation, portrait: portrait, hair: hair, matteExplanation: detail)
    }

    func refineDepth(_ image: CIImage, region: CGRect, existing: CIImage, method: DepthRefinementMethod, engine: DepthEngine = .anything, cancellation: DepthCancellation? = nil) throws -> DepthRefinementResult {
        try localModel.refine(image, region: region, existing: existing, method: method, engine: engine, cancellation: cancellation)
    }

    func refine(_ image: CIImage, region: CGRect, existing: CIImage) throws -> CIImage {
        let crop = region.intersection(image.extent)
        guard crop.width >= 48, crop.height >= 48 else { return existing }
        // Re-run accurate segmentation on the full-resolution region, then feather the join.
        let local = image.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        try VNImageRequestHandler(ciImage: local, options: [:]).perform([request])
        guard let result = request.results?.first else { throw LutelierError.message("No portrait edges found in this area. Include some of the head or body in the selection.") }
        let mask = fit(CIImage(cvPixelBuffer: result.pixelBuffer, options: [.colorSpace: NSNull()]), to: local.extent)
            .transformed(by: CGAffineTransform(translationX: crop.minX, y: crop.minY))
        let feather = CIImage(color: .white).cropped(to: crop)
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 12]).cropped(to: image.extent)
        return mask.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: existing, kCIInputMaskImageKey: feather]).cropped(to: image.extent)
    }

    private func fit(_ image: CIImage, to extent: CGRect) -> CIImage {
        PortraitMatteService.fit(image, to: extent)
    }

    private func hasForeground(_ image: CIImage) -> Bool {
        let extent = CGRect(x: 0, y: 0, width: 32, height: 32)
        var samples = [Float](repeating: 0, count: 32 * 32)
        let mask = PortraitMatteService.fit(image, to: extent)
        samples.withUnsafeMutableBytes { CIContext(options: [.workingColorSpace: NSNull()]).render(mask, toBitmap: $0.baseAddress!, rowBytes: 32 * 4, bounds: extent, format: .Rf, colorSpace: nil) }
        return samples.filter { $0.isFinite && $0 > 0.1 }.count >= 4
    }

    private func normalize(_ data: AVDepthData, extent: CGRect) -> CIImage {
        let converted = data.converting(toDepthDataType: kCVPixelFormatType_DisparityFloat32)
        let buffer = converted.depthDataMap
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer) / MemoryLayout<Float>.stride
        let pointer = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: Float.self)
        var values: [Float] = []
        for y in 0..<height { for x in 0..<width { let v = pointer[y * stride + x]; if v.isFinite && v > 0 { values.append(v) } } }
        values.sort()
        let low = values.isEmpty ? Float(0) : values[values.count / 100]
        let high = values.isEmpty ? Float(1) : values[min(values.count - 1, values.count * 99 / 100)]
        let scale = 1 / max(high - low, 0.0001)
        let raw = CIImage(cvPixelBuffer: buffer, options: [.colorSpace: NSNull()]).applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: CGFloat(scale), y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: CGFloat(scale), y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: CGFloat(scale), y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: CGFloat(-low * scale), y: CGFloat(-low * scale), z: CGFloat(-low * scale), w: 0)])
        return fit(raw.applyingFilter("CIColorClamp"), to: extent)
    }
}
