import Vision
import CoreImage
import AVFoundation
import ImageIO

struct DepthResult {
    var subject: CIImage?
    var depth: CIImage?
    var explanation: String
}

/// Vision mattes identify people; they are never presented as metric depth.
final class DepthService {
    func analyze(_ image: CIImage, captured: AVDepthData? = nil) throws -> DepthResult {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        try VNImageRequestHandler(ciImage: image, options: [:]).perform([request])
        let mask = request.results?.first.map { fit(CIImage(cvPixelBuffer: $0.pixelBuffer), to: image.extent) }
        let depth = captured.map { normalize($0, extent: image.extent) }
        return DepthResult(subject: mask, depth: depth, explanation: depth != nil
            ? "Captured depth • near and far planes available"
            : mask != nil ? "Portrait mask • background blur available; near depth needs a depth photo"
            : "No person or captured depth found. Try a portrait or a depth-enabled capture.")
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
        let mask = fit(CIImage(cvPixelBuffer: result.pixelBuffer), to: local.extent)
            .transformed(by: CGAffineTransform(translationX: crop.minX, y: crop.minY))
        let feather = CIImage(color: .white).cropped(to: crop)
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 12]).cropped(to: image.extent)
        return mask.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: existing, kCIInputMaskImageKey: feather]).cropped(to: image.extent)
    }

    private func fit(_ image: CIImage, to extent: CGRect) -> CIImage {
        image.transformed(by: CGAffineTransform(scaleX: extent.width / image.extent.width, y: extent.height / image.extent.height))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY)).cropped(to: extent)
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
        let raw = CIImage(cvPixelBuffer: buffer).applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: CGFloat(scale), y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: CGFloat(scale), y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: CGFloat(scale), y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: CGFloat(-low * scale), y: CGFloat(-low * scale), z: CGFloat(-low * scale), w: 0)])
        return fit(raw.applyingFilter("CIColorClamp"), to: extent)
    }
}
