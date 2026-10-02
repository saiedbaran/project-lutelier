import AVFoundation
import CoreImage
import ImageIO

struct PortraitMattes {
    var portrait: CIImage?
    var hair: CIImage?
    var available: Bool { portrait != nil || hair != nil }
}

enum AnalysisTexture: String, CaseIterable {
    case photo = "Photo", depth = "Depth", portrait = "Portrait", hair = "Hair"
}

/// Capture mattes are coverage/alpha images. They never replace the scalar depth map.
enum PortraitMatteService {
    static func read(_ data: Data, portrait: AVPortraitEffectsMatte? = nil, hair: AVSemanticSegmentationMatte? = nil) -> PortraitMattes {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return PortraitMattes() }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = CGImagePropertyOrientation(rawValue: (properties?[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1) ?? .up
        var portrait = portrait, hair = hair
        if portrait == nil, let info = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypePortraitEffectsMatte) as? [AnyHashable: Any] {
            portrait = try? AVPortraitEffectsMatte(fromDictionaryRepresentation: info)
        }
        if hair == nil, let info = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeSemanticSegmentationHairMatte) as? [AnyHashable: Any] {
            hair = try? AVSemanticSegmentationMatte(fromDictionaryRepresentation: info)
        }
        return PortraitMattes(
            portrait: portrait.map { CIImage(cvPixelBuffer: $0.applyingExifOrientation(orientation).mattingImage, options: [.colorSpace: NSNull()]) },
            hair: hair.map { CIImage(cvPixelBuffer: $0.applyingExifOrientation(orientation).mattingImage, options: [.colorSpace: NSNull()]) })
    }

    static func fit(_ image: CIImage, to extent: CGRect) -> CIImage {
        image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
            .transformed(by: CGAffineTransform(scaleX: extent.width / image.extent.width, y: extent.height / image.extent.height))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY)).cropped(to: extent)
    }

    static func crop(_ mattes: PortraitMattes, imageExtent: CGRect, region: CGRect) -> PortraitMattes {
        func cropped(_ image: CIImage?) -> CIImage? {
            image.map { fit($0, to: imageExtent).cropped(to: region)
                .transformed(by: CGAffineTransform(translationX: -region.minX, y: -region.minY)) }
        }
        return PortraitMattes(portrait: cropped(mattes.portrait), hair: cropped(mattes.hair))
    }

    static func subject(portrait: CIImage?, hair: CIImage?, fallback: CIImage?, extent: CGRect) -> CIImage? {
        // A coarse Vision mask must not overwrite the fractional capture matte's hair edges.
        let base = (portrait ?? fallback).map { fit($0, to: extent) }
        guard let hair else { return base }
        let fine = fit(hair, to: extent)
        guard let base else { return fine }
        return fine.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: base]).cropped(to: extent)
    }

    static func protect(_ blurMask: CIImage, subject: CIImage?) -> CIImage {
        guard let subject else { return blurMask }
        let background = fit(subject, to: blurMask.extent).applyingFilter("CIColorInvert")
        return blurMask.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: background]).cropped(to: blurMask.extent)
    }
}
