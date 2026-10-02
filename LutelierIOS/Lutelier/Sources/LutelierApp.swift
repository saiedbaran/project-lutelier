import SwiftUI

@main
struct LutelierApp: App {
    var body: some Scene { WindowGroup { LutelierRootView() } }
}

struct LutelierRootView: View {
    @State private var launching = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            EditorView()
            if launching {
                ZStack {
                    Palette.ink.ignoresSafeArea()
                    VStack(spacing: 8) {
                        Image("BrandIcon").resizable().scaledToFit().frame(width: 230, height: 230)
                        Text("LUTELIER").font(.system(size: 36, weight: .black)).tracking(1.5)
                        Text("THE ART OF PHOTOGRAPHY").font(.system(size: 12, weight: .medium)).tracking(1.2).foregroundStyle(.white.opacity(0.75))
                    }.foregroundStyle(.white)
                }.transition(.opacity).zIndex(100)
            }
        }.task {
            try? await Task.sleep(for: .milliseconds(1600))
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.4)) { launching = false }
        }
    }
}

#Preview("Lutelier · iPhone") { EditorView() }
