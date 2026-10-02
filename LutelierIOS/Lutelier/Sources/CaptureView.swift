import SwiftUI

struct CaptureView: View {
    @StateObject private var camera = CameraService()
    @Environment(\.dismiss) private var dismiss
    @State private var grid = true
    @State private var timer = 0
    @State private var countdown = 0
    @State private var cameraVisible = true
    @State private var aspect = "4:3"
    @State private var fullScreenRatio: CGFloat = 0.46
    let onCapture: (CaptureResult) -> Void
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            GeometryReader { geometry in
                let ratio = aspect == "Full Screen" ? geometry.size.width / geometry.size.height : aspect == "1:1" ? CGFloat(1) : aspect == "16:9" ? CGFloat(9.0 / 16.0) : CGFloat(3.0 / 4.0)
                let width = aspect == "Full Screen" ? geometry.size.width : min(geometry.size.width, (geometry.size.height - 210) * ratio)
                CameraPreview(session: camera.session, onFocus: camera.focusAt)
                    .frame(width: width, height: width / ratio).clipped()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, aspect == "Full Screen" ? 0 : 100)
                    .onAppear { fullScreenRatio = geometry.size.width / geometry.size.height }
                    .onChange(of: geometry.size) { fullScreenRatio = geometry.size.width / geometry.size.height }
            }.ignoresSafeArea()
            if grid {
                GeometryReader { geometry in
                    Path { path in
                        for fraction in [CGFloat(1.0 / 3.0), CGFloat(2.0 / 3.0)] {
                            path.move(to: CGPoint(x: geometry.size.width * fraction, y: 0)); path.addLine(to: CGPoint(x: geometry.size.width * fraction, y: geometry.size.height))
                            path.move(to: CGPoint(x: 0, y: geometry.size.height * fraction)); path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height * fraction))
                        }
                    }.stroke(.white.opacity(0.2), lineWidth: 0.5)
                }.allowsHitTesting(false)
            }
            VStack(spacing: 16) {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }.accessibilityLabel("Close camera")
                    Button { grid.toggle() } label: { Image(systemName: "grid").frame(width: 44, height: 44) }.accessibilityLabel("Toggle grid")
                    Button { camera.flash.toggle() } label: { Image(systemName: camera.flash ? "bolt.fill" : "bolt.slash").frame(width: 44, height: 44) }.accessibilityLabel("Toggle flash").tint(camera.flash ? Palette.amber : .white)
                    Button { timer = timer == 0 ? 3 : timer == 3 ? 10 : 0 } label: { Image(systemName: "timer").frame(width: 44, height: 44).overlay(alignment: .bottomTrailing) { if timer > 0 { Text("\(timer)s").font(.caption2) } } }.accessibilityLabel("Cycle capture timer")
                    Button {
                        if let current = camera.lenses.first(where: { $0.uniqueID == camera.selectedLens }), let next = camera.lenses.first(where: { $0.position != current.position }) { camera.selectLens(next.uniqueID) }
                    } label: { Image(systemName: "camera.rotate").frame(width: 44, height: 44) }.accessibilityLabel("Switch camera")
                }.padding(6).lutelierGlass()
                Spacer()
                if countdown > 0 { Text("\(countdown)").font(.system(size: 80, weight: .thin)).shadow(radius: 12) }
                if let error = camera.error { Text(error).font(.caption).padding().background(.black.opacity(0.7), in: .rect(cornerRadius: 16)) }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(camera.lenses, id: \.uniqueID) { lens in
                            Button(lens.localizedName) { camera.selectLens(lens.uniqueID) }.buttonStyle(.bordered).font(.caption2).tint(camera.selectedLens == lens.uniqueID ? Palette.amber : .white)
                        }
                    }
                }
                VStack(spacing: 12) {
                    if camera.manual {
                    HStack(alignment: .bottom, spacing: 1) { ForEach(Array(camera.histogram.enumerated()), id: \.offset) { _, value in Rectangle().fill(Palette.amber.opacity(0.75)).frame(height: max(1, value * 30)) } }.frame(height: 30).accessibilityLabel("Live exposure histogram")
                    HStack {
                        Toggle("RAW", isOn: $camera.useRAW).disabled(!camera.rawAvailable)
                    }.font(.caption)
                    if camera.manual {
                        ScrollView {
                            VStack(spacing: 10) {
                                setting("ISO", value: $camera.iso, range: camera.isoBounds).disabled(!camera.exposureAvailable)
                                VStack {
                                    HStack { Text("Shutter"); Spacer(); Text(camera.shutter < 1 ? "1/\(Int(1 / camera.shutter)) s" : "1 s").monospacedDigit() }.font(.caption)
                                    Slider(value: Binding(get: { log2(camera.shutter) }, set: { camera.shutter = exp2($0); camera.applyControls() }), in: -13...0)
                                }.disabled(!camera.exposureAvailable)
                                setting("Manual focus", value: $camera.focus, range: 0...1).disabled(!camera.focusAvailable)
                                setting("White balance (K)", value: $camera.kelvin, range: 2500...10000).disabled(!camera.whiteBalanceAvailable)
                                setting("Tint", value: $camera.tint, range: -100...100).disabled(!camera.whiteBalanceAvailable)
                            }
                        }.frame(maxHeight: 175)
                    }
                    Toggle("Capture depth", isOn: $camera.useDepth).font(.caption).disabled(!camera.depthAvailable || camera.useRAW)
                    setting("Zoom", value: $camera.zoom, range: 1...max(camera.zoomLimit, 1.01))
                    Text(camera.useRAW ? "RAW + JPEG • DNG original stored in your library • depth off" : camera.depthAvailable ? "JPEG • depth available on this camera" : "JPEG • this camera does not deliver depth")
                        .font(.caption2).foregroundStyle(.secondary)
                    }
                }.padding(camera.manual ? 16 : 0).lutelierGlass().opacity(camera.manual ? 1 : 0)
                HStack {
                    Button { camera.manual.toggle() } label: { Text("PRO").font(.caption.bold()).tracking(2).frame(maxWidth: .infinity).frame(height: 44).foregroundStyle(camera.manual ? Palette.amber : .white) }.accessibilityLabel("Pro mode").accessibilityValue(camera.manual ? "On" : "Off")
                    Button { Task { await timedCapture() } } label: {
                        Circle().fill(.white).frame(width: 70, height: 70).padding(5).overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 2))
                            .overlay { if camera.capturing { ProgressView().tint(.black) } }
                    }.disabled(!camera.ready || camera.capturing || countdown > 0).accessibilityLabel("Take photograph")
                    Menu {
                        ForEach(["4:3", "1:1", "16:9", "Full Screen"], id: \.self) { choice in Button(choice) { aspect = choice } }
                    } label: { Text(aspect).font(.caption.bold()).frame(maxWidth: .infinity).frame(height: 44) }.accessibilityLabel("Choose aspect ratio")
                }.padding(.vertical, 12)
            }.padding(16)
        }.scrollIndicators(.hidden).preferredColorScheme(.dark).tint(Palette.amber).foregroundStyle(.white).buttonStyle(.plain)
        .task { camera.onCapture = { result in onCapture(croppedCapture(result)) }; await camera.start() }
        .onDisappear { cameraVisible = false; countdown = 0; camera.stop() }
        .onChange(of: camera.manual) { camera.applyControls() }
    }
    private func croppedCapture(_ result: CaptureResult) -> CaptureResult {
        guard let image = UIImage(data: result.processed) else { return result }
        let ratio = aspect == "Full Screen" ? fullScreenRatio : aspect == "1:1" ? CGFloat(1) : aspect == "16:9" ? CGFloat(9.0 / 16.0) : CGFloat(3.0 / 4.0)
        let width = min(image.size.width, image.size.height * ratio), height = width / ratio
        if abs(image.size.width / image.size.height - ratio) < 0.01 { return result }
        let format = UIGraphicsImageRendererFormat(); format.scale = image.scale
        let cropped = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { _ in
            image.draw(at: CGPoint(x: -(image.size.width - width) / 2, y: -(image.size.height - height) / 2))
        }
        guard let processed = cropped.jpegData(compressionQuality: 0.96) else { return result }
        // Crop already-oriented coverage with the same centered framing as the photograph.
        let mattes = PortraitMatteService.read(result.processed, portrait: result.portrait, hair: result.hair)
        let full = CGRect(origin: .zero, size: image.size)
        let region = CGRect(x: (image.size.width - width) / 2, y: (image.size.height - height) / 2, width: width, height: height)
        let croppedMattes = PortraitMatteService.crop(mattes, imageExtent: full, region: region)
        // Sensor disparity is re-estimated by Core ML for the cropped frame.
        return CaptureResult(processed: processed, raw: result.raw, depth: nil, orientedMattes: croppedMattes)
    }
    @MainActor private func timedCapture() async {
        if timer > 0 {
            countdown = timer
            while countdown > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard cameraVisible else { return }
                countdown -= 1
            }
        }
        guard camera.ready, cameraVisible else { return }
        camera.capture()
    }
    private func setting(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(spacing: 2) {
            HStack { Text(label); Spacer(); Text(value.wrappedValue, format: .number.precision(.fractionLength(label.contains("seconds") ? 5 : 0))).monospacedDigit() }.font(.caption)
            Slider(value: value, in: range).onChange(of: value.wrappedValue) { camera.applyControls() }.accessibilityLabel(label)
        }
    }
}
