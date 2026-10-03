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
                    .frame(width: 64, height: 64).blur(radius: 17).opacity(configuration.isPressed ? 0.95 : 0.65)
            }
            .shadow(color: .black.opacity(configuration.isPressed ? 0 : 0.65), radius: 9, x: shadowX, y: shadowY)
            .rotationEffect(.degrees(configuration.isPressed && !reduceMotion ? 90 : 0))
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
    case looks = "Looks", depth = "Depth", adjust = "Adjust", studio = "Studio"
    var symbol: String {
        switch self {
        case .looks: "camera.filters"
        case .depth: "viewfinder"
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
    var apertureBlades = 6
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
        apertureBlades = min(9, max(3, Int((try c.decodeIfPresent(Double.self, forKey: .apertureBlades) ?? 6).rounded())))
        protectPortraitEdges = try c.decodeIfPresent(Bool.self, forKey: .protectPortraitEdges) ?? true
        lightPower = try c.decodeIfPresent(Double.self, forKey: .lightPower) ?? 0.5
        lightAngle = try c.decodeIfPresent(Double.self, forKey: .lightAngle) ?? 0.3
    }
}

struct ToolGlassPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .glassEffect(.regular.interactive(), in: Capsule())
            .contentShape(Capsule())
            .hoverEffect(.highlight)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// One shared glass island with a native interactive overlay on the pressed item.
struct GlassIslandButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Capsule())
            .glassEffect(configuration.isPressed ? .regular.interactive() : .identity, in: Capsule())
            .hoverEffect(.highlight)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.35)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
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
    func glassIsland() -> some View {
        self.padding(4).glassEffect(.regular.interactive(), in: Capsule())
            .buttonStyle(GlassIslandButtonStyle())
    }
    func lutelierGlass() -> some View {
        self.glassEffect(.regular, in: .rect(cornerRadius: 28))
    }
}

/// Let UIKit own the system tab selection, liquid lens, and accessibility semantics.
struct NativeToolTabs: UIViewRepresentable {
    @Binding var selection: ToolTab
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITabBar {
        let bar = UITabBar()
        bar.delegate = context.coordinator
        bar.overrideUserInterfaceStyle = .dark
        bar.tintColor = UIColor(Palette.amber)
        bar.items = ToolTab.allCases.enumerated().map { index, tab in
            UITabBarItem(title: tab.rawValue, image: UIImage(systemName: tab.symbol), tag: index)
        }
        bar.layer.cornerRadius = 28; bar.layer.cornerCurve = .continuous; bar.clipsToBounds = true
        return bar
    }
    func updateUIView(_ bar: UITabBar, context: Context) {
        context.coordinator.parent = self
        bar.selectedItem = bar.items?[ToolTab.allCases.firstIndex(of: selection) ?? 0]
    }
    final class Coordinator: NSObject, UITabBarDelegate {
        var parent: NativeToolTabs
        init(_ parent: NativeToolTabs) { self.parent = parent }
        func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
            parent.selection = ToolTab.allCases[item.tag]
        }
    }
}
