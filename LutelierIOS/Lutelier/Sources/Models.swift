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
    var body: some View {
        Image("BrandIcon").resizable()
            .frame(width: size, height: size).scaleEffect(1.31)
            .frame(width: size, height: size).clipShape(Circle())
            .shadow(color: .black.opacity(0.65), radius: size * 0.12, x: motion.x, y: motion.y)
    }
}

struct CameraLensPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
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

enum ToolTab: String, CaseIterable { case looks = "Looks", grain = "Grain", depth = "Depth", light = "Light", studio = "Studio", adjust = "Adjust" }
enum Bokeh: String, Codable, CaseIterable { case soft = "Soft", disc = "Disc", ring = "Ring" }
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
    var light = StudioLight.off
    var lightPower = 0.5
    var lightAngle = 0.3
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
