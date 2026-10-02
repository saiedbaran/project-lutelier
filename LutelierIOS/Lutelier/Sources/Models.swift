import SwiftUI
import CoreImage
import CoreMotion

@MainActor
final class LensMotion: ObservableObject {
    @Published var x: CGFloat = 0
    @Published var y: CGFloat = 6
    private let manager = CMMotionManager()
    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            let gx = motion.gravity.x, gy = motion.gravity.y
            Task { @MainActor [weak self] in
                guard let self, self.manager.isDeviceMotionActive else { return }
                let targetX = CGFloat(-gx * 12), targetY = CGFloat(6 + gy * 9)
                self.x += (targetX - self.x) * 0.18
                self.y += (targetY - self.y) * 0.18
            }
        }
    }
    func stop() { manager.stopDeviceMotionUpdates(); x = 0; y = 6 }
}

struct LensLogo: View {
    @ObservedObject var motion: LensMotion
    var size: CGFloat
    var castsShadow = true
    var body: some View {
        Image("BrandIcon").resizable()
            .frame(width: size, height: size).scaleEffect(1.31)
            .frame(width: size, height: size).clipShape(Circle())
            .shadow(color: .black.opacity(castsShadow ? 0.65 : 0), radius: size * 0.12, x: motion.x, y: motion.y)
    }
}

struct CameraLensPressStyle: ButtonStyle {
    var shadowX: CGFloat = 0
    var shadowY: CGFloat = 6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                Circle().fill(AngularGradient(colors: [.teal, .blue, .purple, .indigo, .teal], center: .center))
                    .frame(width: 64, height: 64).blur(radius: 17).opacity(configuration.isPressed ? 0.85 : 0)
            }
            .shadow(color: .black.opacity(configuration.isPressed ? 0 : 0.65), radius: 9, x: shadowX, y: shadowY)
            .rotationEffect(.degrees(configuration.isPressed ? 90 : 0))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
            .contentShape(Circle())
    }
}

struct Look: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let category: String
    let description: String
    let file: String
    let dimension: Int
    let fx: [String: Double]
    var sha256: String?
    static let original = Look(id: "original", name: "Original", category: "All", description: "Your unedited photograph", file: "", dimension: 0, fx: [:])
}

enum ToolTab: String, CaseIterable {
    case looks = "Looks", grain = "Grain", depth = "Depth", light = "Light", studio = "Studio", adjust = "Adjust"
    var symbol: String {
        switch self {
        case .looks: "camera.filters"
        case .grain: "aqi.medium"
        case .depth: "viewfinder"
        case .light: "sun.max"
        case .studio: "sparkle"
        case .adjust: "slider.horizontal.3"
        }
    }
}
enum Bokeh: String, Codable, CaseIterable { case soft = "Soft", disc = "Disc", ring = "Ring", anamorphic = "Anamorphic", polygon = "Polygon" }
enum StudioLight: String, Codable, CaseIterable { case off = "Natural", softbox = "Softbox", rembrandt = "Rembrandt", split = "Split", rim = "Rim", stage = "Stage" }

struct Recipe: Codable, Equatable {
    var lookID = "original"
    var strength = 1.0
    var exposure = 0.0
    var temperature = 6500.0
    var saturation = 1.0
    var grain = 0.0
    var grainSize = 1.0
    var grainColor = 0.2
    var glow = 0.0
    var halation = 0.0
    var vignette = 0.0
    var texture = 0.0
    var nearBlur = 0.0
    var farBlur = 0.0
    var focusDepth = 0.5
    var bokeh = Bokeh.soft
    var bokehHighlights = 0.0
    var catEye = 0.0
    var apertureRotation = 0.0
    var bokehBloom = 0.0
    var highlightSensitivity = 0.7
    var anamorphicRatio = 2.0
    var apertureBlades = 6.0
    var protectPortraitEdges = true
    var light = StudioLight.off
    var lightPower = 0.5
    var lightAngle = 0.3
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lookID = try c.decodeIfPresent(String.self, forKey: .lookID) ?? "original"
        bokeh = try c.decodeIfPresent(Bokeh.self, forKey: .bokeh) ?? .soft
        light = try c.decodeIfPresent(StudioLight.self, forKey: .light) ?? .off
        strength = try c.decodeIfPresent(Double.self, forKey: .strength) ?? 1
        exposure = try c.decodeIfPresent(Double.self, forKey: .exposure) ?? 0
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature) ?? 6500
        saturation = try c.decodeIfPresent(Double.self, forKey: .saturation) ?? 1
        grain = try c.decodeIfPresent(Double.self, forKey: .grain) ?? 0
        grainSize = try c.decodeIfPresent(Double.self, forKey: .grainSize) ?? 1
        grainColor = try c.decodeIfPresent(Double.self, forKey: .grainColor) ?? 0.2
        glow = try c.decodeIfPresent(Double.self, forKey: .glow) ?? 0
        halation = try c.decodeIfPresent(Double.self, forKey: .halation) ?? 0
        vignette = try c.decodeIfPresent(Double.self, forKey: .vignette) ?? 0
        texture = try c.decodeIfPresent(Double.self, forKey: .texture) ?? 0
        nearBlur = try c.decodeIfPresent(Double.self, forKey: .nearBlur) ?? 0
        farBlur = try c.decodeIfPresent(Double.self, forKey: .farBlur) ?? 0
        focusDepth = try c.decodeIfPresent(Double.self, forKey: .focusDepth) ?? 0.5
        bokehHighlights = try c.decodeIfPresent(Double.self, forKey: .bokehHighlights) ?? 0
        catEye = try c.decodeIfPresent(Double.self, forKey: .catEye) ?? 0
        apertureRotation = try c.decodeIfPresent(Double.self, forKey: .apertureRotation) ?? 0
        bokehBloom = try c.decodeIfPresent(Double.self, forKey: .bokehBloom) ?? 0
        highlightSensitivity = try c.decodeIfPresent(Double.self, forKey: .highlightSensitivity) ?? 0.7
        anamorphicRatio = try c.decodeIfPresent(Double.self, forKey: .anamorphicRatio) ?? 2
        apertureBlades = try c.decodeIfPresent(Double.self, forKey: .apertureBlades) ?? 6
        protectPortraitEdges = try c.decodeIfPresent(Bool.self, forKey: .protectPortraitEdges) ?? true
        lightPower = try c.decodeIfPresent(Double.self, forKey: .lightPower) ?? 0.5
        lightAngle = try c.decodeIfPresent(Double.self, forKey: .lightAngle) ?? 0.3
    }
}

struct ToolGlassPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background {
            if configuration.isPressed { Capsule().fill(.clear).glassEffect(.regular, in: Capsule()) }
        }
    }
}

struct PhotoRecord: Codable, Identifiable {
    var id: UUID
    var filename: String
    var date: Date
    var recipe: Recipe
    var sourcePhotoID: UUID? = nil
    var studioTemplateID: String? = nil
    var isAIGenerated: Bool? = nil
}

enum LutelierError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

enum Palette {
    static let amber = Color(red: 1, green: 0.71, blue: 0.28)
    static let ink = Color(red: 0.055, green: 0.055, blue: 0.075)
}

extension View {
    func lutelierGlass() -> some View {
        self.glassEffect(.regular, in: .rect(cornerRadius: 28))
    }
}
