import Foundation
import CoreGraphics
import CoreImage

enum DepthRefinementMethod: String, CaseIterable {
    case contextual = "Context crop"
    case overlapping = "Overlapping tiles"
}

struct DepthRefinementResult {
    var image: CIImage
    var acceptedTiles: Int
    var rejectedTiles: Int
}

/// Original deterministic fusion, inspired by coarse/fine depth research; not learned PatchFusion.
enum DepthPatchFusion {
    struct Alignment {
        var scale: Double
        var bias: Double
        var consistency: Float
        func value(_ v: Float) -> Float { Float(scale * Double(v) + bias) }
    }

    static func alignment(global: [Float], local: [Float], width: Int, height: Int, support: CGRect) throws -> Alignment {
        guard width > 0, height > 0, global.count == width * height, local.count == global.count else { throw LutelierError.message("Depth texture sizes do not match.") }
        let bounds = support.intersection(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        guard !bounds.isEmpty else { throw LutelierError.message("This patch has no alignment context.") }
        var pairs: [(Double, Double)] = []
        for y in stride(from: Int(ceil(bounds.minY)), to: Int(floor(bounds.maxY)), by: 3) {
            for x in stride(from: Int(ceil(bounds.minX)), to: Int(floor(bounds.maxX)), by: 3) {
                let a = Double(local[y * width + x]), b = Double(global[y * width + x])
                if a.isFinite && b.isFinite { pairs.append((a,b)) }
            }
        }
        guard pairs.count >= 16 else { throw LutelierError.message("Not enough context to align this depth patch.") }
        var scale = 1.0, bias = 0.0, correlation = 0.0, error = 0.0
        for pass in 0..<2 {
            let n = Double(pairs.count), sx = pairs.reduce(0) { $0 + $1.0 }, sy = pairs.reduce(0) { $0 + $1.1 }
            let vx = pairs.reduce(0) { $0 + $1.0 * $1.0 } - sx * sx / n
            let vy = pairs.reduce(0) { $0 + $1.1 * $1.1 } - sy * sy / n
            let covariance = pairs.reduce(0) { $0 + $1.0 * $1.1 } - sx * sy / n
            guard vx > 0.00001, vy > 0.00001 else { throw LutelierError.message("This crop is too flat to align safely. Include nearby objects or edges.") }
            scale = covariance / vx; bias = (sy - scale * sx) / n
            correlation = covariance / sqrt(vx * vy)
            guard scale > 0.05, scale < 20 else { throw LutelierError.message("The crop conflicts with the existing depth. Try a wider box.") }
            if pass == 0 {
                let residuals = pairs.map { abs(scale * $0.0 + bias - $0.1) }.sorted()
                let threshold = max(0.005, residuals[residuals.count * 8 / 10])
                pairs = pairs.filter { abs(scale * $0.0 + bias - $0.1) <= threshold }
                guard pairs.count >= 16 else { throw LutelierError.message("Not enough consistent depth context.") }
            } else {
                error = sqrt(pairs.reduce(0) { $0 + pow(scale * $1.0 + bias - $1.1, 2) } / n)
            }
        }
        // Heuristic consistency checks, not calibrated model confidence.
        guard correlation >= 0.35, error <= 0.12 else { throw LutelierError.message("This tile disagrees with the scene depth and was rejected.") }
        return Alignment(scale: scale, bias: bias, consistency: Float(max(0.15, min(1, correlation * exp(-error / 0.08)))))
    }

    static func edgeWeight(x: Int, y: Int, rect: CGRect) -> Float {
        guard rect.contains(CGPoint(x: CGFloat(x), y: CGFloat(y))) else { return 0 }
        let feather = max(2, min(rect.width, rect.height) * 0.12)
        let distance = min(CGFloat(x) - rect.minX, rect.maxX - CGFloat(x), CGFloat(y) - rect.minY, rect.maxY - CGFloat(y))
        let t = Float(min(1, max(0, distance / feather)))
        return t * t * (3 - 2 * t)
    }

    static func merge(global: [Float], local: [Float], width: Int, height: Int, selection: CGRect, support: CGRect) throws -> [Float] {
        let fit = try alignment(global: global, local: local, width: width, height: height, support: support)
        var result = global
        for y in 0..<height { for x in 0..<width {
            let weight = edgeWeight(x: x, y: y, rect: selection), i = y * width + x
            let value = fit.value(local[i])
            if weight > 0, value.isFinite { result[i] = global[i] * (1 - weight) + min(1, max(0, value)) * weight }
        } }
        return result
    }

    /// Fixed anchor and weighted accumulation avoid tile-order dependent overwrites.
    struct Accumulator {
        let anchor: [Float]
        let width: Int, height: Int
        private var sum: [Float]
        private var weights: [Float]
        init(anchor: [Float], width: Int, height: Int) {
            precondition(anchor.count == width * height)
            self.anchor = anchor; self.width = width; self.height = height
            sum = anchor.map { $0 * 0.35 }; weights = [Float](repeating: 0.35, count: anchor.count)
        }
        mutating func add(local: [Float], support: CGRect) throws {
            let fit = try DepthPatchFusion.alignment(global: anchor, local: local, width: width, height: height, support: support)
            for y in max(0, Int(ceil(support.minY)))..<min(height, Int(floor(support.maxY))) {
                for x in max(0, Int(ceil(support.minX)))..<min(width, Int(floor(support.maxX))) {
                    let i = y * width + x, value = fit.value(local[i])
                    guard value.isFinite else { continue }
                    let disagreement = abs(value - anchor[i]) / 0.12
                    let weight = DepthPatchFusion.edgeWeight(x: x, y: y, rect: support) * fit.consistency / (1 + disagreement * disagreement)
                    sum[i] += min(1, max(0, value)) * weight; weights[i] += weight
                }
            }
        }
        func finish(original: [Float], selection: CGRect) -> [Float] {
            precondition(original.count == anchor.count)
            var result = original
            for y in 0..<height { for x in 0..<width {
                let i = y * width + x, weight = DepthPatchFusion.edgeWeight(x: x, y: y, rect: selection)
                if weight > 0 { result[i] = original[i] * (1 - weight) + sum[i] / weights[i] * weight }
            } }
            return result
        }
    }

    static func tiles(in rect: CGRect) -> [CGRect] {
        let w = rect.width * 0.68, h = rect.height * 0.68
        return [rect.minY, rect.maxY - h].flatMap { y in [rect.minX, rect.maxX - w].map { x in CGRect(x: x, y: y, width: w, height: h) } }
    }
}
