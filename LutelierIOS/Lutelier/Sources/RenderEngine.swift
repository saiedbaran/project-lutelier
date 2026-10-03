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
        // Relative disparity controls circle-of-confusion radius, not blend opacity.
        float m = clamp((value - 0.025) / 0.5, 0.0, 1.0);
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
                    image = try blur(image, mask: mask, amount: recipe.farBlur, recipe: recipe, subject: recipe.protectPortraitEdges ? depth.subject.map(fitted) : nil)
                }
                if recipe.nearBlur > 0, let mask = planeKernel.apply(extent: extent, arguments: [map, recipe.focusDepth, 1.0]) {
                    image = try blur(image, mask: mask, amount: recipe.nearBlur, recipe: recipe, subject: recipe.protectPortraitEdges ? depth.subject.map(fitted) : nil, nearPlane: true)
                }
            } else if let subject = depth.subject.map(fitted), recipe.farBlur > 0 {
                let background = subject.applyingFilter("CIColorInvert")
                image = try blur(image, mask: background, amount: recipe.farBlur, recipe: recipe, subject: subject)
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

    // Occlusion-aware normalized aperture integration. The colour source and its
    // visibility are sampled together, so a foreground cannot contaminate a far
    // layer before compositing. Inspired by layered DoF literature (Dr.Bokeh),
    // not an implementation of its learned preprocessing or hidden geometry.
    private let depthApertureKernel = CIKernel(source: """
    kernel vec4 depthAperture(sampler image, sampler cocMap, sampler protection,
        sampler donorVisibility, float radius, float oval, float blades,
        float ring, float rotation, float catEye, float soft, vec2 center,
        vec2 halfSize, float sensitivity, float highlightGain, float nearPlane) {
        vec2 p = destCoord();
        vec4 original = sample(image, samplerTransform(image, p));
        float coc = clamp(sample(cocMap, samplerTransform(cocMap, p)).r, 0.0, 1.0);
        float subjectCoverage = clamp(sample(protection, samplerTransform(protection, p)).r, 0.0, 1.0);
        if (subjectCoverage > 0.999 || (nearPlane < 0.5 && radius * coc < 0.25)) { return original; }
        vec2 edge = (p - center) / halfSize;
        float edgeAmount = min(length(edge), 1.0) * catEye;
        vec2 radial = edge / max(length(edge), 0.001);
        vec3 sum = vec3(0.0);
        vec3 brightSum = vec3(0.0);
        vec3 backgroundSum = vec3(0.0);
        float backgroundWeight = 0.0;
        float total = 0.0;
        float apertureWeight = 0.0;
        float footprint = mix(coc, 1.0, nearPlane);
        for (int i = 0; i < 192; i++) {
            float theta = float(i) * 2.39996323;
            float r = sqrt((float(i) + 0.5) / 192.0);
            // Sample the full pupil for near scatter; shape its source footprint below.
            float pupilR = mix(r, sqrt(0.72 + 0.28 * r * r), ring * (1.0-nearPlane));
            float polygon = 1.0;
            if (blades > 2.0) {
                float pi = 3.14159265;
                float a = mod(theta, 2.0*pi/blades) - pi/blades;
                polygon = cos(pi/blades) / cos(a);
                pupilR *= mix(polygon, 1.0, nearPlane);
            }
            vec2 pupil = vec2(cos(theta), sin(theta)) * pupilR;
            float weight = 1.0 - smoothstep(0.90, 1.02,
                length(pupil + radial * edgeAmount * 0.7));
            weight *= mix(1.0, exp(-3.0*r*r), soft);
            vec2 shaped = vec2(pupil.x / oval, pupil.y);
            vec2 delta = vec2(shaped.x * cos(rotation) - shaped.y * sin(rotation),
                             shaped.x * sin(rotation) + shaped.y * cos(rotation)) * radius * footprint;
            vec2 q = p + delta;
            vec4 colour = sample(image, samplerTransform(image, q));
            float sourceCoC = clamp(sample(cocMap, samplerTransform(cocMap, q)).r, 0.0, 1.0);
            float visibility = clamp(sample(donorVisibility, samplerTransform(donorVisibility, q)).r, 0.0, 1.0);
            apertureWeight += weight;
            if (nearPlane < 0.5) {
                // Reject sharp/nearer donors, normalize the remaining background.
                weight *= smoothstep(0.005, 0.025, sourceCoC)
                    * smoothstep(coc - 0.08, coc - 0.02, sourceCoC) * visibility;
            } else {
                // Gather a foreground scatter footprint, including coverage outside
                // the original silhouette. Reconstruct only newly exposed border pixels.
                float bg = weight * (1.0-smoothstep(0.005, 0.025, sourceCoC));
                backgroundSum += colour.rgb * bg; backgroundWeight += bg;
                float support = max(sourceCoC * polygon, 0.001);
                float coverage = 1.0-smoothstep(support-0.025, support+0.025, r);
                coverage *= mix(1.0, smoothstep(support*0.80, support*0.88, r), ring);
                float pupilArea = mix(1.0, 0.28, ring);
                if (blades > 2.0) { pupilArea *= blades * sin(6.2831853/blades) / 6.2831853; }
                float gaussian = exp(-3.0*r*r/max(sourceCoC*sourceCoC,0.001)+3.0*r*r);
                weight *= coverage * smoothstep(0.005, 0.025, sourceCoC) * visibility
                    * mix(1.0, gaussian, soft) / max(sourceCoC*sourceCoC*pupilArea, 0.001);
            }
            float luminance = dot(colour.rgb, vec3(0.2126,0.7152,0.0722));
            float bright = smoothstep(1.0-sensitivity*0.75, 1.0, luminance);
            sum += colour.rgb * weight;
            brightSum += colour.rgb * bright * weight;
            total += weight;
        }
        if (total < 0.0001) { return original; }
        vec3 result = sum / total;
        vec3 glow = clamp(brightSum / total * highlightGain, 0.0, 1.0);
        result += (vec3(1.0)-clamp(result,0.0,1.0))*glow;
        if (nearPlane > 0.5) {
            vec3 behind = original.rgb;
            if (backgroundWeight > 0.001) {
                behind = mix(behind, backgroundSum/backgroundWeight, smoothstep(0.005,0.025,coc));
            }
            result = mix(behind, result, clamp(total/max(apertureWeight,0.001),0.0,1.0));
        }
        return vec4(mix(result, original.rgb, subjectCoverage), original.a);
    }
    """)

    func blur(_ image: CIImage, mask: CIImage, amount: Double, recipe: Recipe,
              subject: CIImage? = nil, nearPlane: Bool = false) throws -> CIImage {
        guard amount > 0 else { return image }
        let extent = image.extent
        let style = recipe.bokeh
        let radius = amount * extent.width / 35
        let protection = subject.map { PortraitMatteService.fit($0, to: extent) }
            ?? CIImage(color: .black).cropped(to: extent)
        // Mixed foreground/background edge colours are unsafe background donors.
        // A small donor-only inset avoids a sharp expanded silhouette in the output.
        let visibility = protection.applyingFilter("CIColorInvert")
            .clampedToExtent().applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: max(0.5, extent.width / 1200)])
            .cropped(to: extent)
        guard let output = depthApertureKernel?.apply(extent: extent,
            roiCallback: { _, rect in rect.insetBy(dx: -radius-2, dy: -radius-2) },
            arguments: [image.clampedToExtent(), mask.clampedToExtent(), protection.clampedToExtent(), visibility.clampedToExtent(), radius,
                style == .anamorphic ? max(1, recipe.anamorphicRatio) : 1,
                style == .polygon ? Double(recipe.apertureBlades) : 0,
                style == .ring ? 1.0 : 0.0, recipe.apertureRotation * .pi / 180,
                recipe.catEye, style == .soft ? 1.0 : 0.0,
                CIVector(x: extent.midX, y: extent.midY), CIVector(x: extent.width / 2, y: extent.height / 2),
                recipe.highlightSensitivity, recipe.bokehHighlights + recipe.bokehBloom * 0.5,
                nearPlane ? 1.0 : 0.0]) else {
            throw LutelierError.message("The depth-aware aperture renderer is unavailable on this device.")
        }
        return output.cropped(to: extent)
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
