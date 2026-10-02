import XCTest
import CoreImage
import UIKit
@testable import Lutelier

final class RenderTests: XCTestCase {
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
            CIContext().render(image, toBitmap: $0.baseAddress!, rowBytes: width * 16,
                bounds: image.extent, format: .RGBAf, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        }
        return pixels
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
        withUnsafeMutableBytes(of: &value) { CIContext().render(image, toBitmap: $0.baseAddress!, rowBytes: 4, bounds: CGRect(x: floor(image.extent.midX), y: floor(image.extent.midY), width: 1, height: 1), format: .Rf, colorSpace: CGColorSpaceCreateDeviceGray()) }
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
