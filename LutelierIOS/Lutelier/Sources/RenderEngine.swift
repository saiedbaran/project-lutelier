import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

final class RenderEngine {
    let context = CIContext(options: [.cacheIntermediates: false])
    private var cubes: [String: Data] = [:]
    private let grainKernel = CIColorKernel(source: """
    kernel vec4 filmGrain(__sample s, float amount, float size, float chroma) {
        vec2 p = floor(destCoord() / max(size, 0.5));
        float n = fract(sin(dot(p, vec2(12.9898,78.233))) * 43758.5453) - 0.5;
        float c = fract(sin(dot(p, vec2(93.989,67.345))) * 24634.6345) - 0.5;
        float lum = dot(s.rgb, vec3(0.2126,0.7152,0.0722));
        float weight = 0.35 + 0.65 * (1.0 - abs(lum * 2.0 - 1.0));
        vec3 noise = mix(vec3(n), vec3(n,c,-c), chroma);
        return vec4(clamp(s.rgb + noise * amount * 0.24 * weight, 0.0, 1.0), s.a);
    }
    """)
    private let planeKernel = CIColorKernel(source: """
    kernel vec4 plane(__sample d, float focus, float nearPlane) {
        float value = mix(focus - d.r, d.r - focus, nearPlane);
        float m = smoothstep(0.025, 0.25, value);
        return vec4(m,m,m,1.0);
    }
    """)
    private let lightKernel = CIColorKernel(source: """
    kernel vec4 studio(__sample s, __sample m, vec2 dimensions, float power, float angle, float mode) {
        vec2 uv = destCoord() / dimensions;
        float key = clamp(0.5 + (uv.x - 0.5) * cos(angle * 6.28318) + (uv.y - 0.5) * sin(angle * 6.28318),0.0,1.0);
        float shape = mix(key, smoothstep(0.35,0.65,key), step(1.5,mode));
        shape = mix(shape, pow(abs(key - 0.5)*2.0,3.0), step(3.5,mode));
        float ev = (shape - 0.35) * power * 2.0 * m.r;
        vec3 rgb = s.rgb * exp2(ev);
        float background = 1.0 - m.r;
        rgb *= 1.0 - background * power * step(4.5,mode) * 0.9;
        return vec4(clamp(rgb,0.0,1.0),s.a);
    }
    """)

    func render(_ original: CIImage, recipe: Recipe, look: Look, depth: DepthResult?, maxDimension: CGFloat? = nil) throws -> UIImage {
        if recipe.grain > 0 && grainKernel == nil { throw LutelierError.message("Film-grain processing is unavailable on this device.") }
        if (recipe.nearBlur > 0 || recipe.farBlur > 0), depth?.depth != nil, planeKernel == nil { throw LutelierError.message("Depth-plane processing is unavailable on this device.") }
        if recipe.light != .off, depth?.subject != nil, lightKernel == nil { throw LutelierError.message("Studio-light processing is unavailable on this device.") }
        var input = original
        if let maxDimension, max(input.extent.width, input.extent.height) > maxDimension {
            let scale = maxDimension / max(input.extent.width, input.extent.height)
            input = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        let extent = input.extent
        var image = input
        if look.dimension > 0 {
            let data = try cube(look)
            let graded = input.applyingFilter("CIColorCubeWithColorSpace", parameters: ["inputCubeDimension": look.dimension, "inputCubeData": data, "inputColorSpace": CGColorSpace(name: CGColorSpace.sRGB)!])
            let blend = CIFilter.dissolveTransition()
            blend.inputImage = input; blend.targetImage = graded; blend.time = Float(recipe.strength)
            image = blend.outputImage ?? input
        }
        image = image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: recipe.exposure])
            .applyingFilter("CITemperatureAndTint", parameters: ["inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: recipe.temperature, y: 0)])
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: recipe.saturation])
        if recipe.texture != 0 {
            if recipe.texture > 0 { image = image.applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: recipe.texture]) }
            else {
                let smooth = image.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: abs(recipe.texture) * extent.width / 700]).cropped(to: extent)
                let blend = CIFilter.dissolveTransition(); blend.inputImage = image; blend.targetImage = smooth; blend.time = Float(abs(recipe.texture) * 0.55)
                image = blend.outputImage ?? image
            }
        }
        func fitted(_ source: CIImage) -> CIImage {
            source.transformed(by: CGAffineTransform(scaleX: extent.width / source.extent.width, y: extent.height / source.extent.height)).cropped(to: extent)
        }
        if let depth {
            if let map = depth.depth.map(fitted), let planeKernel {
                if recipe.farBlur > 0, let mask = planeKernel.apply(extent: extent, arguments: [map, recipe.focusDepth, 0.0]) {
                    image = try blur(image, mask: PortraitMatteService.protect(mask, subject: recipe.protectPortraitEdges ? depth.subject : nil), amount: recipe.farBlur, recipe: recipe)
                }
                if recipe.nearBlur > 0, let mask = planeKernel.apply(extent: extent, arguments: [map, recipe.focusDepth, 1.0]) {
                    image = try blur(image, mask: PortraitMatteService.protect(mask, subject: recipe.protectPortraitEdges ? depth.subject : nil), amount: recipe.nearBlur, recipe: recipe)
                }
            } else if let subject = depth.subject.map(fitted), recipe.farBlur > 0 {
                let background = subject.applyingFilter("CIColorInvert")
                image = try blur(image, mask: background, amount: recipe.farBlur, recipe: recipe)
            }
            if let subject = depth.subject.map(fitted), recipe.light != .off, let lightKernel {
                let mode = Double(StudioLight.allCases.firstIndex(of: recipe.light) ?? 0)
                image = lightKernel.apply(extent: extent, arguments: [image, subject, CIVector(x: extent.width, y: extent.height), recipe.lightPower, recipe.lightAngle, mode]) ?? image
            }
        }
        if recipe.glow > 0 { image = image.applyingFilter("CIBloom", parameters: [kCIInputRadiusKey: extent.width / 180, kCIInputIntensityKey: recipe.glow * 0.5]).cropped(to: extent) }
        if recipe.halation > 0 {
            let highlights = image.applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: -0.7, kCIInputContrastKey: 3])
                .applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0.15, y: 0, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: recipe.halation * 0.3)])
                .clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: extent.width / 250]).cropped(to: extent)
            image = highlights.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: image])
        }
        image = image.applyingFilter("CIVignette", parameters: [kCIInputIntensityKey: recipe.vignette, kCIInputRadiusKey: extent.width * 0.65])
        if recipe.grain > 0, let grainKernel {
            image = grainKernel.apply(extent: extent, arguments: [image, recipe.grain, recipe.grainSize * extent.width / 1600, recipe.grainColor]) ?? image
        }
        guard let cg = context.createCGImage(image.cropped(to: extent), from: extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else { throw LutelierError.message("Could not render this photograph.") }
        return UIImage(cgImage: cg)
    }

    // Idealized aperture integration, not a measured lens PSF. Keep a normalized
    // aperture so uniform backgrounds do not brighten when the shape changes.
    private let apertureKernel = CIKernel(source: """
    kernel vec4 aperture(sampler image, float radius, float oval, float blades,
                         float ring, float rotation, float catEye, vec2 center,
                         vec2 halfSize, float sensitivity, float highlightsOnly) {
        vec4 sum = vec4(0.0);
        float total = 0.0;
        vec2 edge = (destCoord() - center) / halfSize;
        float edgeAmount = min(length(edge), 1.0) * catEye;
        vec2 radial = edge / max(length(edge), 0.001);
        for (int i = 0; i < 96; i++) {
            float theta = float(i) * 2.39996323;
            float r = sqrt((float(i) + 0.5) / 96.0);
            r = mix(r, sqrt(0.72 + 0.28 * r * r), ring);
            if (blades > 2.0) {
                float pi = 3.14159265;
                float a = mod(theta, 2.0*pi/blades) - pi/blades;
                r *= cos(pi/blades) / cos(a);
            }
            vec2 pupil = vec2(cos(theta), sin(theta)) * r;
            // Intersection with an offset pupil clips the peripheral aperture.
            float weight = 1.0 - smoothstep(0.90, 1.02,
                length(pupil + radial * edgeAmount * 0.7));
            vec2 shaped = vec2(pupil.x / oval, pupil.y);
            vec2 delta = vec2(shaped.x * cos(rotation) - shaped.y * sin(rotation),
                              shaped.x * sin(rotation) + shaped.y * cos(rotation)) * radius;
            vec4 c = sample(image, samplerTransform(image, destCoord() + delta));
            float l = dot(c.rgb, vec3(0.2126,0.7152,0.0722));
            float bright = smoothstep(1.0 - sensitivity * 0.75, 1.0, l);
            sum += vec4(c.rgb * mix(1.0, bright, highlightsOnly), c.a) * weight;
            total += weight;
        }
        return sum / max(total, 0.001);
    }
    """)
    private let opticalCompositeKernel = CIColorKernel(source: """
    kernel vec4 optical(__sample base, __sample highlights, float gain) {
        // Bounded screen addition keeps the base intact at zero highlight gain.
        vec3 glow = clamp(highlights.rgb * gain, 0.0, 1.0);
        return vec4(base.rgb + (vec3(1.0) - clamp(base.rgb, 0.0, 1.0)) * glow, base.a);
    }
    """)
    func blur(_ image: CIImage, mask: CIImage, amount: Double, recipe: Recipe) throws -> CIImage {
        let style = recipe.bokeh
        let radius = amount * image.extent.width / 35
        let extent = image.extent
        func aperture(_ source: CIImage, highlightsOnly: Double) throws -> CIImage {
            guard let output = apertureKernel?.apply(extent: extent,
                roiCallback: { _, rect in rect.insetBy(dx: -radius, dy: -radius) },
                arguments: [source.clampedToExtent(), radius,
                    style == .anamorphic ? recipe.anamorphicRatio : 1,
                    style == .polygon ? recipe.apertureBlades.rounded() : 0,
                    style == .ring ? 1.0 : 0.0, recipe.apertureRotation * .pi / 180,
                    recipe.catEye, CIVector(x: extent.midX, y: extent.midY),
                    CIVector(x: extent.width / 2, y: extent.height / 2),
                    recipe.highlightSensitivity, highlightsOnly]) else {
                throw LutelierError.message("The optical aperture renderer is unavailable on this device.")
            }
            return output
        }
        let blurred: CIImage
        if style == .anamorphic || style == .polygon || recipe.catEye > 0 || recipe.apertureRotation != 0 {
            blurred = try aperture(image, highlightsOnly: 0)
        } else if style == .soft {
            blurred = image.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
        } else {
            blurred = image.clampedToExtent().applyingFilter("CIBokehBlur", parameters: [kCIInputRadiusKey: radius, "inputRingAmount": style == .ring ? 0.8 : 0.0, "inputRingSize": 0.1, "inputSoftness": 0.6])
        }
        var optical = blurred.cropped(to: extent)
        if recipe.bokehHighlights > 0 || recipe.bokehBloom > 0 {
            // Extract highlights from the original plane before aperture integration.
            // Mask first so sharp foreground lights do not feed background bloom.
            let black = CIImage(color: .black).cropped(to: extent)
            let plane = image.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: black, kCIInputMaskImageKey: mask])
            var highlights = try aperture(plane, highlightsOnly: 1)
            if recipe.bokehBloom > 0 {
                highlights = highlights.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius * recipe.bokehBloom * 0.5]).cropped(to: extent)
            }
            guard let output = opticalCompositeKernel?.apply(extent: extent, arguments: [optical, highlights, recipe.bokehHighlights + recipe.bokehBloom * 0.5]) else {
                throw LutelierError.message("Bokeh highlight processing is unavailable on this device.")
            }
            optical = output
        }
        return optical.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: image, kCIInputMaskImageKey: mask]).cropped(to: extent)
    }

    func cube(_ look: Look) throws -> Data {
        if let cached = cubes[look.id] { return cached }
        let url = Bundle.main.url(forResource: look.file, withExtension: nil, subdirectory: "Looks")
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Looks/" + look.file)
        let data = try Data(contentsOf: url)
        guard data.count == look.dimension * look.dimension * look.dimension * 16 else { throw LutelierError.message("This LUT has an invalid size.") }
        cubes[look.id] = data
        return data
    }
}
