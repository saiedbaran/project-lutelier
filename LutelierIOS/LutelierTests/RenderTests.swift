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
        var recipe = old; recipe.bokeh = .anamorphic; recipe.anamorphicRatio = 2.4; recipe.bokehBloom = 0.5
        XCTAssertEqual(try JSONDecoder().decode(Recipe.self, from: JSONEncoder().encode(recipe)), recipe)
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
