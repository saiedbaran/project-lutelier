import SwiftUI
import PhotosUI
import AVFoundation

private enum CameraTool: String, CaseIterable, Identifiable {
    case flash = "Flash", live = "Live", aspect = "Aspect", timer = "Timer", exposure = "Exposure", styles = "Styles", depth = "Depth", night = "Low light", format = "Format", aperture = "Aperture", focus = "Focus", shutter = "Shutter", whiteBalance = "White balance", histogram = "Histogram", grid = "Grid"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .flash: "bolt.fill"; case .live: "livephoto"; case .aspect: "aspectratio"; case .timer: "timer"; case .exposure: "plusminus"; case .styles: "camera.filters"; case .depth: "f.cursive"; case .night: "moon"; case .format: "photo"; case .aperture: "camera.aperture"; case .focus: "viewfinder"; case .shutter: "stopwatch"; case .whiteBalance: "thermometer.medium"; case .histogram: "chart.bar.xaxis"; case .grid: "grid"
        }
    }
}

struct CaptureView: View {
    @StateObject private var camera = CameraService()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var drawer
    @State private var grid = true
    @State private var timer = 0
    @State private var countdown = 0
    @State private var cameraVisible = true
    @State private var aspect = "4:3"
    @State private var fullScreenRatio: CGFloat = 0.46
    @State private var controlsVisible: Bool
    @State private var tool: CameraTool?
    @State private var showHistogram = false
    @State private var style = "Natural"
    @State private var libraryPicker: PhotosPickerItem?
    let previewOnly: Bool
    let onImport: ((PhotosPickerItem) -> Void)?
    let onCapture: (CaptureResult) -> Void
    init(previewOnly: Bool = false, showControls: Bool = false, onImport: ((PhotosPickerItem) -> Void)? = nil, onCapture: @escaping (CaptureResult) -> Void) {
        self.previewOnly = previewOnly; self.onImport = onImport; self.onCapture = onCapture
        _controlsVisible = State(initialValue: showControls)
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                let ratio = aspect == "Full Screen" ? geometry.size.width / geometry.size.height : aspect == "1:1" ? CGFloat(1) : aspect == "16:9" ? CGFloat(9.0/16.0) : CGFloat(3.0/4.0)
                let width = min(geometry.size.width, (geometry.size.height - 120) * ratio)
                ZStack {
                    CameraPreview(session: camera.session, onFocus: camera.focusAt)
                    if grid {
                        Path { path in
                            for fraction in [CGFloat(1.0/3.0), CGFloat(2.0/3.0)] {
                                path.move(to: CGPoint(x: width*fraction, y: 0)); path.addLine(to: CGPoint(x: width*fraction, y: width/ratio))
                                path.move(to: CGPoint(x: 0, y: width/ratio*fraction)); path.addLine(to: CGPoint(x: width, y: width/ratio*fraction))
                            }
                        }.stroke(.white.opacity(0.28), lineWidth: 0.5).allowsHitTesting(false)
                    }
                }.frame(width: width, height: width/ratio).clipped().frame(maxHeight: .infinity, alignment: .top).padding(.top, 72)
                VStack(spacing: 10) {
                    HStack {
                        Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }.accessibilityLabel("Close camera")
                        Spacer()
                        Button { changeDrawer(nil) } label: { Image(systemName: controlsVisible ? "chevron.down" : "chevron.up").frame(width: 44, height: 44) }.accessibilityLabel("Camera controls")
                        Spacer()
                        Button { changeDrawer(.flash) } label: { Image(systemName: camera.flash ? "bolt.fill" : "bolt.slash").frame(width: 44, height: 44) }.accessibilityLabel("Flash")
                    }.buttonStyle(ToolGlassPressStyle())
                    if camera.manual {
                        HStack(spacing: 0) {
                            readout("f/" + String(format: "%.1f", camera.aperture), caption: "APERTURE", tool: .aperture)
                            readout("\(Int(camera.iso))", caption: "ISO", tool: .shutter)
                            readout(shutterText, caption: "SHUTTER", tool: .shutter)
                            readout(camera.autoFocus ? "AF" : "MF", caption: "FOCUS", tool: .focus)
                            readout(camera.autoWhiteBalance ? "AWB" : "\(Int(camera.kelvin))", caption: "WB", tool: .whiteBalance)
                            readout(String(format: "%+.1f", camera.bias), caption: "EV", tool: .exposure)
                        }.glassIsland()
                    }
                    if showHistogram {
                        HStack(alignment: .bottom, spacing: 1) {
                            ForEach(Array(camera.histogram.enumerated()), id: \.offset) { _, value in Rectangle().fill(Palette.amber).frame(height: max(1, value*38)) }
                        }.frame(width: 125, height: 40).padding(8).glassEffect().frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Spacer(minLength: 4)
                    if countdown > 0 { Text("\(countdown)").font(.system(size: 72, weight: .light)).shadow(radius: 10) }
                    if let error = camera.error { Text(error).font(.caption).padding(10).glassEffect() }
                    if !backLenses.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(backLenses, id: \.uniqueID) { lens in
                            Button { camera.selectLens(lens.uniqueID) } label: {
                                Text(lens.deviceType == .builtInUltraWideCamera ? "0.5×" : lens.deviceType == .builtInTelephotoCamera ? "Tele" : "1×")
                                    .font(.caption.weight(.semibold)).foregroundStyle(camera.selectedLens == lens.uniqueID ? Palette.amber : .white).frame(width: 48, height: 40)
                            }
                        }
                    }.glassIsland()
                    }
                    HStack(spacing: 12) {
                        Button { camera.manual = false; camera.applyControls() } label: { Text("PHOTO").font(.caption.weight(.semibold)).frame(width: 86, height: 40).foregroundStyle(!camera.manual ? Palette.amber : .white) }
                        Button { camera.manual = true; camera.applyControls() } label: { Text("PRO").font(.caption.weight(.semibold)).frame(width: 86, height: 40).foregroundStyle(camera.manual ? Palette.amber : .white) }
                    }.glassIsland()
                    HStack {
                        PhotosPicker(selection: $libraryPicker, matching: .images, preferredItemEncoding: .current) { Image(systemName: "photo.on.rectangle").frame(width: 54, height: 54) }.accessibilityLabel("Open photo library")
                        Spacer()
                        Button { Task { await timedCapture() } } label: {
                            Circle().fill(.white).frame(width: 64, height: 64).padding(5).overlay(Circle().stroke(.white, lineWidth: 3))
                                .overlay { if camera.capturing { ProgressView().tint(.black) } }
                        }.buttonStyle(.plain).disabled(!camera.ready || camera.capturing || countdown > 0).accessibilityLabel("Take photograph")
                        Spacer()
                        Button { camera.switchCamera() } label: { Image(systemName: "arrow.triangle.2.circlepath.camera").frame(width: 54, height: 54) }.accessibilityLabel("Switch camera")
                    }.padding(.horizontal, 8)
                    if controlsVisible { controlDrawer.transition(.move(edge: .bottom).combined(with: .opacity)) }
                }.padding(.horizontal, 16).padding(.vertical, 8)
            }.onAppear { fullScreenRatio = geometry.size.width / geometry.size.height }
        }.preferredColorScheme(.dark).tint(Palette.amber).foregroundStyle(.white).buttonStyle(.glass)
            .task {
                guard !previewOnly else { return }
                camera.onCapture = { result in
                    var output = croppedCapture(result)
                    var recipe = Recipe()
                    if style == "Warm" { recipe.temperature = 7200 }
                    if style == "Cool" { recipe.temperature = 4700 }
                    if style == "Mono" { recipe.saturation = 0 }
                    output.initialRecipe = recipe; onCapture(output)
                }
                await camera.start()
            }
            .onChange(of: libraryPicker) { _, item in if let item { onImport?(item) } }
            .onDisappear { cameraVisible = false; countdown = 0; camera.stop() }
    }
    private var backLenses: [AVCaptureDevice] {
        camera.lenses.filter { $0.position == .back && [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera].contains($0.deviceType) }
            .sorted { $0.activeFormat.videoFieldOfView > $1.activeFormat.videoFieldOfView }
    }
    private var shutterText: String { camera.shutter < 1 ? "1/\(max(1, Int(1/camera.shutter)))" : String(format: "%.1fs", camera.shutter) }
    private func changeDrawer(_ selection: CameraTool?) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) {
            if selection == nil && controlsVisible && tool == nil { controlsVisible = false }
            else { controlsVisible = true; tool = selection }
        }
    }
    private func readout(_ value: String, caption: String, tool: CameraTool) -> some View {
        Button { changeDrawer(tool) } label: {
            VStack(spacing: 2) { Text(value).font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7); Text(caption).font(.system(size: 7)) }.frame(maxWidth: .infinity, minHeight: 40)
        }
    }
    private var controlDrawer: some View {
        GlassEffectContainer {
            VStack(spacing: 12) {
                HStack {
                    Button { if tool != nil { changeDrawer(nil) } else { withAnimation { controlsVisible = false } } } label: { Image(systemName: tool == nil ? "xmark" : "chevron.left").frame(width: 44, height: 44) }
                    Spacer()
                    Text(tool?.rawValue.uppercased() ?? "CAMERA CONTROLS").font(.caption.weight(.semibold)).tracking(1)
                    Spacer()
                    Button { withAnimation { controlsVisible = false } } label: { Image(systemName: "checkmark").frame(width: 44, height: 44) }.accessibilityLabel("Done")
                }.buttonStyle(GlassIslandButtonStyle())
                if let tool { toolControl(tool) }
                else {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                            ForEach(CameraTool.allCases) { item in
                                Button { changeDrawer(item) } label: {
                                    VStack(spacing: 7) { Image(systemName: item.symbol).font(.title3).frame(height: 24); Text(item.rawValue).font(.caption2).lineLimit(1) }.frame(maxWidth: .infinity, minHeight: 52)
                                }.buttonStyle(GlassIslandButtonStyle())
                            }
                        }
                    }.frame(maxHeight: 320)
                }
            }.padding(12).glassEffect(.regular.interactive(), in: .rect(cornerRadius: 30)).glassEffectID("camera-drawer", in: drawer)
        }
    }
    @ViewBuilder private func toolControl(_ selected: CameraTool) -> some View {
        switch selected {
        case .flash:
            Toggle("Flash", isOn: $camera.flash).disabled(!camera.flashAvailable)
            if !camera.flashAvailable { Text("Flash is unavailable on this camera.").font(.caption) }
        case .live:
            Toggle("Live Photo", isOn: $camera.useLivePhoto).disabled(!camera.livePhotoAvailable || camera.useRAW)
                .onChange(of: camera.useLivePhoto) { _, enabled in if enabled { aspect = "4:3" } }
            Text("Keep the paired motion clip. Save it with ‘Save Live Photo original’ in the editor menu.").font(.caption).foregroundStyle(.secondary)
        case .aspect:
            Picker("Aspect", selection: $aspect) { ForEach(["4:3", "1:1", "16:9", "Full Screen"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented).disabled(camera.useLivePhoto)
        case .timer:
            Picker("Timer", selection: $timer) { ForEach([0, 3, 5, 10], id: \.self) { Text($0 == 0 ? "Off" : "\($0)s").tag($0) } }.pickerStyle(.segmented)
        case .exposure:
            setting("Exposure compensation", value: $camera.bias, range: camera.exposureBiasBounds, defaultValue: 0).disabled(camera.manual && !camera.autoExposure)
            if camera.manual && !camera.autoExposure { Text("Enable Auto in Shutter / ISO to use exposure compensation.").font(.caption).foregroundStyle(.secondary) }
        case .styles:
            Picker("Style", selection: $style) { ForEach(["Natural", "Warm", "Cool", "Mono"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented)
            Text("Applied to the captured photograph; adjustable in the editor.").font(.caption).foregroundStyle(.secondary)
        case .depth:
            Toggle("Capture portrait depth", isOn: $camera.useDepth).disabled(!camera.depthAvailable || camera.useRAW)
            Text(camera.useRAW ? "Turn RAW off to capture portrait and hair mattes." : camera.depthAvailable ? "Portrait and hair coverage are captured when supported and a person is detected." : "This lens does not deliver capture depth. Scene depth remains available in the editor.").font(.caption).foregroundStyle(.secondary)
        case .night:
            Text("Apple’s multi-frame Night mode is not exposed to this app. For a steady, longer exposure, use these shutter presets.").font(.caption).foregroundStyle(.secondary)
            HStack { ForEach([0.125, 0.25, 1.0], id: \.self) { duration in Button(String(format: "%.3gs", duration)) { camera.manual = true; camera.autoExposure = false; camera.shutter = min(duration, camera.shutterBounds.upperBound); camera.applyControls() }.frame(maxWidth: .infinity) } }.disabled(!camera.exposureAvailable)
        case .format:
            Toggle("HEIF (smaller files)", isOn: $camera.useHEIF)
            Toggle("RAW + processed photo", isOn: $camera.useRAW).disabled(!camera.rawAvailable).onChange(of: camera.useRAW) { _, enabled in if enabled { camera.useLivePhoto = false } }
        case .aperture:
            if camera.apertureStops.isEmpty { Text("This camera has a fixed f/\(String(format: "%.1f", camera.aperture)) aperture. Adjustable optical aperture requires a supported camera.").font(.subheadline) }
            else {
                Toggle("Auto aperture", isOn: $camera.autoAperture).onChange(of: camera.autoAperture) { camera.applyControls() }
                HStack { ForEach(camera.apertureStops, id: \.self) { stop in Button("f/\(String(format: "%.1f", stop))") { camera.autoAperture = false; camera.aperture = stop; camera.applyControls() } } }
            }
        case .focus:
            Toggle("Autofocus", isOn: $camera.autoFocus).onChange(of: camera.autoFocus) { camera.manual = true; camera.applyControls() }
            setting("Focus", value: $camera.focus, range: 0...1, defaultValue: 0.5).disabled(camera.autoFocus || !camera.focusAvailable)
        case .shutter:
            Toggle("Auto exposure", isOn: $camera.autoExposure).onChange(of: camera.autoExposure) { camera.manual = true; camera.applyControls() }
            setting("ISO", value: $camera.iso, range: camera.isoBounds, defaultValue: min(max(100, camera.isoBounds.lowerBound), camera.isoBounds.upperBound)).disabled(camera.autoExposure || !camera.exposureAvailable)
            setting("Shutter · " + shutterText, value: Binding(get: { log2(max(camera.shutter, 0.00001)) }, set: { camera.shutter = exp2($0) }), range: log2(camera.shutterBounds.lowerBound)...log2(camera.shutterBounds.upperBound), defaultValue: log2(1.0/125.0)).disabled(camera.autoExposure || !camera.exposureAvailable)
        case .whiteBalance:
            Toggle("Auto white balance", isOn: $camera.autoWhiteBalance).onChange(of: camera.autoWhiteBalance) { camera.manual = true; camera.applyControls() }
            setting("Temperature (K)", value: $camera.kelvin, range: 2500...10000, defaultValue: 5500).disabled(camera.autoWhiteBalance || !camera.whiteBalanceAvailable)
            setting("Tint", value: $camera.tint, range: -100...100, defaultValue: 0).disabled(camera.autoWhiteBalance || !camera.whiteBalanceAvailable)
        case .histogram: Toggle("Live exposure histogram", isOn: $showHistogram)
        case .grid: Toggle("Rule-of-thirds grid", isOn: $grid)
        }
    }
    private func setting(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, defaultValue: Double) -> some View {
        VStack(spacing: 4) {
            HStack { Text(title); Spacer(); if !title.hasPrefix("Shutter") { Text(value.wrappedValue, format: .number.precision(.fractionLength(title == "ISO" || title.contains("(K)") ? 0 : 2))).monospacedDigit() } }.font(.caption)
            SnapSlider(value: value, range: range, defaultValue: defaultValue).onChange(of: value.wrappedValue) { camera.applyControls() }.accessibilityLabel(title)
        }
    }
    private func croppedCapture(_ result: CaptureResult) -> CaptureResult {
        if result.liveMovie != nil { return result } // Preserve the original still/movie pairing.
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
}
