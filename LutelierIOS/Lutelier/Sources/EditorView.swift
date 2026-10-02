import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

private struct ToolTabFrames: PreferenceKey {
    static var defaultValue: [ToolTab: CGRect] = [:]
    static func reduce(value: inout [ToolTab: CGRect], nextValue: () -> [ToolTab: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}

private struct EditorInformation: Identifiable {
    let id = UUID()
    var title: String
    var detail: String
    var source: URL? = nil
}

struct EditorView: View {
    @Namespace private var toolSelection
    @State private var tabFrames: [ToolTab: CGRect] = [:]
    @GestureState private var hoveredTab: ToolTab?
    @StateObject private var store = EditorStore()
    @StateObject private var studio = StudioStore()
    @StateObject private var lensMotion = LensMotion()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var analysisTexture = AnalysisTexture.photo
    @State private var selectingDepth = false
    @State private var depthSelection: CGRect?
    @State private var pendingLookID: String?
    @State private var lookTransition: Task<Void, Never>?
    @State private var picker: PhotosPickerItem?
    @State private var tab = ToolTab.looks
    @State private var category = "All"
    @State private var compare = false
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var showAssistant = false
    @State private var showStudio = false
    @State private var importLUT = false
    @State private var information: EditorInformation?
    @State private var visibleRegion = CGRect(x: 0, y: 0, width: 1, height: 1)
    var filteredLooks: [Look] { store.looks.filter { category == "All" || $0.category == category } }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Palette.ink.ignoresSafeArea()
                if let image = store.preview {
                    GeometryReader { backdrop in
                        Image(uiImage: image).resizable().scaledToFill().frame(width: backdrop.size.width, height: backdrop.size.height).blur(radius: 65).scaleEffect(1.15).opacity(0.3)
                    }.ignoresSafeArea().allowsHitTesting(false)
                }
                VStack(spacing: 14) {
                    header
                    if let image = store.preview {
                        ZStack(alignment: .bottom) {
                            if compare, let original = store.originalPreview { ComparisonPhoto(before: original, after: image) }
                            else { ZoomPhoto(image: analysisTexture == .depth ? (store.depthPreview ?? image) : analysisTexture == .portrait ? (store.portraitPreview ?? image) : analysisTexture == .hair ? (store.hairPreview ?? image) : image, visibleRegion: $visibleRegion).id(store.selectedPhotoID) }
                            if selectingDepth && tab == .depth && !compare { DepthSelectionOverlay(image: image, visibleRegion: visibleRegion, selection: $depthSelection) }
                            if analysisTexture != .photo { VStack { Text(analysisTexture == .depth ? "Relative depth - white is near" : analysisTexture == .hair ? "Hair coverage - alpha matte" : "Portrait coverage - alpha matte").font(.caption2).padding(8).background(.black.opacity(0.65), in: Capsule()); Spacer() }.padding(12).allowsHitTesting(false) }
                            HStack(spacing: 8) {
                                Text(compare ? "Slide to compare" : "Pinch to explore").font(.caption2).foregroundStyle(.secondary)
                                Spacer()
                                Text(store.currentLook.name).font(.caption.weight(.medium))
                            }.padding(12).background(.ultraThinMaterial, in: Capsule()).padding(14).allowsHitTesting(false).zIndex(50)
                        }
                        .clipShape(.rect(cornerRadius: (geometry.size.width - 32) * 0.09, style: .continuous))
                        .background { Image(uiImage: image).resizable().scaledToFill().blur(radius: 35).opacity(0.45).scaleEffect(1.08).allowsHitTesting(false) }
                    } else { welcome }
                    if store.hasPhoto { inspector.frame(height: tab == .studio ? 195 : tab == .adjust ? 240 : min(geometry.size.height * (tab == .looks || tab == .depth ? 0.43 : 0.34), tab == .looks || tab == .depth ? 340 : 290)) }
                    bottomBar
                }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)
                if store.busy { ProgressView().padding(22).lutelierGlass().accessibilityLabel("Processing photograph") }
            }
        }
        .tint(Palette.amber).preferredColorScheme(.dark)
        .scrollIndicators(.hidden)
        .onAppear { if !reduceMotion { lensMotion.start() } }
        .onDisappear { lensMotion.stop(); lookTransition?.cancel() }
        .onChange(of: scenePhase) { _, phase in if phase == .active && !reduceMotion { lensMotion.start() } else { lensMotion.stop() } }
        .onChange(of: reduceMotion) { _, reduced in if reduced { lensMotion.stop(); cancelLookTransition() } else if scenePhase == .active { lensMotion.start() } }
        .onChange(of: store.renderedLookID) { _, value in if value == pendingLookID { finishLookTransition() } }
        .onChange(of: store.selectedPhotoID) { _, _ in cancelLookTransition(); depthSelection = nil; selectingDepth = false; analysisTexture = .photo }
        .onChange(of: tab) { _, value in if value != .depth { selectingDepth = false; analysisTexture = .photo } }
        .onChange(of: store.error) { _, error in if error != nil { cancelLookTransition() } }
        .task(id: picker) { if let picker { await store.importPhoto(picker) } }
        .sheet(isPresented: $showCamera) { CaptureView { result in showCamera = false; Task { await store.receiveCapture(result) } } }
        .sheet(isPresented: $showLibrary) { library }
        .sheet(isPresented: $showAssistant) { assistant }
        .sheet(isPresented: $showStudio) { StudioView(editor: store, studio: studio) }
        .sheet(item: $information) { info in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(info.detail).font(.body)
                        if let source = info.source { Link("Model license", destination: source) }
                    }.padding(24)
                }.navigationTitle(info.title).navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { information = nil } } }
                    .background(Palette.ink)
            }.preferredColorScheme(.dark).tint(Palette.amber).presentationDetents([.medium, .large])
        }
        .fileImporter(isPresented: $importLUT, allowedContentTypes: [UTType(filenameExtension: "cube") ?? .plainText]) { result in
            switch result { case .success(let url): store.importCube(url); case .failure(let error): store.error = error.localizedDescription }
        }
        .alert("Lutelier", isPresented: Binding(get: { store.error != nil || store.message != nil }, set: { if !$0 { store.error = nil; store.message = nil } })) {
            Button("OK") { store.error = nil; store.message = nil }
        } message: { Text(store.error ?? store.message ?? "") }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("LUTELIER").font(.system(size: 22, weight: .heavy, design: .default)).tracking(0.8)
                Text("THE ART OF PHOTOGRAPHY").font(.system(size: 8, weight: .medium)).tracking(2).foregroundStyle(.secondary)
            }
            Spacer()
            if store.hasPhoto {
                Button { cancelLookTransition(); store.undo() } label: { Image(systemName: "arrow.uturn.backward") }.disabled(!store.canUndo).accessibilityLabel("Undo")
                Button { cancelLookTransition(); store.redo() } label: { Image(systemName: "arrow.uturn.forward") }.disabled(!store.canRedo).accessibilityLabel("Redo")
                Menu { Button("Reset edits") { cancelLookTransition(); store.reset() }; Button("Import .cube LUT") { importLUT = true }; Button("Editing assistant") { showAssistant = true }; if store.hasRaw { Button("Save RAW original") { Task { await store.exportRaw() } } } } label: { Image(systemName: "ellipsis").frame(width: 36, height: 36).background(.white.opacity(0.06), in: Circle()) }.accessibilityLabel("More tools")
            }
        }.foregroundStyle(.white).buttonStyle(.plain)
    }
    private var welcome: some View {
        VStack(spacing: 24) {
            Spacer()
            LensLogo(motion: lensMotion, size: 126)
            VStack(spacing: 10) {
                Text("Make it feel\nlike a memory.").font(.system(size: 39, weight: .medium, design: .default)).multilineTextAlignment(.center)
                Text("Film colour. Beautiful texture.\nA little light, exactly where it belongs.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            HStack(spacing: 8) { feature("114 looks", icon: "camera.filters"); feature("On device", icon: "sparkles") }
            Spacer()
            PhotosPicker(selection: $picker, matching: .images, photoLibrary: .shared()) { Label("Choose a photograph", systemImage: "plus").font(.headline).frame(maxWidth: .infinity).padding(18).background(Palette.amber, in: Capsule()).foregroundStyle(Palette.ink) }
            Button { showCamera = true } label: { Label("Open camera", systemImage: "camera").padding(14) }
            Spacer(minLength: 0)
        }
    }
    private func feature(_ text: String, icon: String) -> some View { Label(text, systemImage: icon).font(.caption).padding(.horizontal, 14).padding(.vertical, 10).lutelierGlass() }

    private func cancelLookTransition() { lookTransition?.cancel(); pendingLookID = nil }
    private func selectLook(_ look: Look) { cancelLookTransition(); store.select(look) }
    private func finishLookTransition() { pendingLookID = nil }

    private var bottomBar: some View {
        HStack(spacing: 14) {
            HStack {
            Button { showLibrary = true } label: { Image(systemName: "square.grid.2x2").frame(width: 44, height: 44) }.accessibilityLabel("Photo library")
            PhotosPicker(selection: $picker, matching: .images, photoLibrary: .shared()) { Image(systemName: "photo.badge.plus").frame(width: 44, height: 44) }.accessibilityLabel("Import photo")
            if store.hasPhoto {
                Button { withAnimation(.easeInOut(duration: 0.2)) { compare.toggle() } } label: { Image(systemName: "rectangle.lefthalf.inset.filled").frame(width: 44, height: 44).foregroundStyle(compare ? Palette.amber : .white) }.accessibilityLabel("Compare original and edit")
                Button { Task { await store.export() } } label: { Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44).background(Palette.amber, in: Circle()).foregroundStyle(Palette.ink) }.disabled(store.busy).accessibilityLabel("Save edit to Photos")
            }
            }.fixedSize(horizontal: true, vertical: false).padding(6).glassEffect(.regular, in: .rect(cornerRadius: 34, style: .continuous))
            Spacer(minLength: 14)
            Button { showCamera = true } label: {
                LensLogo(motion: lensMotion, size: 68, castsShadow: false)
            }.buttonStyle(CameraLensPressStyle(shadowX: lensMotion.x, shadowY: lensMotion.y)).accessibilityLabel("Capture")
        }.frame(maxWidth: .infinity).foregroundStyle(.white).buttonStyle(ToolGlassPressStyle())
    }

    private var inspector: some View {
        VStack(spacing: 12) {
            GeometryReader { tabsGeometry in HStack(spacing: 0) {
                ForEach(ToolTab.allCases, id: \.self) { item in
                    Button { withAnimation(.snappy(duration: 0.22)) { tab = item } } label: {
                        VStack(spacing: 4) {
                            Image(systemName: item.symbol).font(.system(size: 18, weight: .regular)).frame(height: 20).accessibilityHidden(true)
                            Text(item.rawValue).font(.caption2.weight((hoveredTab ?? tab) == item ? .bold : .regular)).lineLimit(1).minimumScaleFactor(0.8)
                        }.frame(width: tabsGeometry.size.width / CGFloat(ToolTab.allCases.count), height: 54)
                            .background {
                                if (hoveredTab ?? tab) == item { Capsule().fill(.clear).glassEffect(.regular, in: Capsule()).matchedGeometryEffect(id: "tool-selection", in: toolSelection) }
                            }
                            .foregroundStyle((hoveredTab ?? tab) == item ? Palette.amber : .secondary)
                    }.buttonStyle(.plain).accessibilityLabel(item.rawValue)
                    .background(GeometryReader { cell in Color.clear.preference(key: ToolTabFrames.self, value: [item: cell.frame(in: .named("tool-tabs"))]) })
                }
            }.coordinateSpace(name: "tool-tabs")
                .onPreferenceChange(ToolTabFrames.self) { tabFrames = $0 }
                .animation(reduceMotion ? nil : .interactiveSpring(response: 0.2, dampingFraction: 0.85), value: hoveredTab)
                .highPriorityGesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("tool-tabs")).updating($hoveredTab) { value, hovering, _ in
                    hovering = tabFrames.first(where: { $0.value.insetBy(dx: 0, dy: -12).contains(value.location) })?.key
                }.onEnded { value in
                    if let item = tabFrames.first(where: { $0.value.insetBy(dx: 0, dy: -12).contains(value.location) })?.key {
                        withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { tab = item }
                    }
                })
            }.frame(height: 54)
            if tab == .looks { lookControls }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        switch tab {
                        case .grain:
                            informationRow("Grain", detail: "Grain changes amount, size and colour of a repeatable film texture. Texture adds local contrast; Glow softens highlights; Halation adds warm highlight spill; Vignette darkens the frame edges.")
                            HStack { grainPreset("Clean", amount: 0, size: 1); grainPreset("35mm", amount: 0.3, size: 1); grainPreset("Pushed", amount: 0.65, size: 1.5) }
                            control("Grain", key: \.grain, range: 0...1)
                            control("Size", key: \.grainSize, range: 0.5...3)
                            control("Colour", key: \.grainColor, range: 0...1)
                            control("Texture", key: \.texture, range: -1...1)
                            control("Glow", key: \.glow, range: 0...1)
                            control("Halation", key: \.halation, range: 0...1)
                            control("Vignette", key: \.vignette, range: 0...1)
                        case .depth:
                            depthEngineControls
                            HStack {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(Bokeh.allCases, id: \.self) { item in
                                            Button(item.rawValue) { store.edit { $0.bokeh = item } }
                                                .font(.caption.weight(store.recipe.bokeh == item ? .bold : .regular))
                                                .padding(.horizontal, 12).padding(.vertical, 8)
                                                .background(store.recipe.bokeh == item ? Palette.amber.opacity(0.18) : .white.opacity(0.06), in: Capsule())
                                                .foregroundStyle(store.recipe.bokeh == item ? Palette.amber : .secondary)
                                        }
                                    }
                                }.frame(height: 34)
                                informationButton("Bokeh", detail: "Near and Far blur act on either side of the focus plane. White in the depth texture is near. Anamorphic changes oval ratio; Polygon changes aperture blades. Bloom strengthens background highlights, and sensitivity controls which luminosities contribute. Optical blur can leave edge halos; inspect hair and strong lights.")
                            }
                            control("Far blur", key: \.farBlur, range: 0...1).disabled(!store.hasSubject && !store.hasDepth)
                            control("Near blur", key: \.nearBlur, range: 0...1).disabled(!store.hasDepth)
                            control("Focus plane", key: \.focusDepth, range: 0...1).disabled(!store.hasDepth)
                            if store.recipe.bokeh == .anamorphic { control("Oval ratio", key: \.anamorphicRatio, range: 1...3) }
                            if store.recipe.bokeh == .polygon { control("Aperture blades", key: \.apertureBlades, range: 3...9) }
                            control("Background bloom", key: \.bokehBloom, range: 0...1)
                            control("Highlight sensitivity", key: \.highlightSensitivity, range: 0...1)
                            HStack {
                                Toggle("Preserve portrait edges", isOn: Binding(get: { store.recipe.protectPortraitEdges }, set: { value in store.edit { $0.protectPortraitEdges = value } })).disabled(!store.hasSubject)
                                informationButton("Portrait edges", detail: "\(store.matteStatus)\n\nCaptured Apple portrait/hair mattes are coverage images, not depth. Vision accurate person segmentation is the fallback. Protection reduces blur on subject edges. Hair inspection is available only when Apple supplied a hair matte.")
                            }
                            Picker("Inspect texture", selection: $analysisTexture) {
                                Text("Photo").tag(AnalysisTexture.photo)
                                if store.hasDepth { Text("Depth").tag(AnalysisTexture.depth) }
                                if store.portraitPreview != nil { Text("Portrait").tag(AnalysisTexture.portrait) }
                                if store.hairPreview != nil { Text("Hair").tag(AnalysisTexture.hair) }
                            }.pickerStyle(.segmented)
                            Toggle("Box select region", isOn: $selectingDepth)
                            informationRow("Refinement", detail: "Draw a box, choose a method, then Refine selected depth. Context crop runs one contextual inference. Overlapping tiles is experimental: one context + four detail crops, with robust scale alignment, consistency checks and feathered blending. It is not the learned PatchFusion network. Depth outside the box and portrait/hair coverage are preserved. More passes take more time and memory; finer geometry is not guaranteed.\n\nCurrent state: \(store.depthStatus)")
                            Picker("Depth refinement", selection: $store.depthRefinementMethod) {
                                ForEach(DepthRefinementMethod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }.pickerStyle(.segmented).disabled(store.busy)
                            Button { guard let region = depthSelection else { return }; Task { await store.refine(normalized: region) } } label: { Label("Refine selected depth", systemImage: "viewfinder") }.disabled(!store.hasDepth || store.busy || depthSelection == nil)
                        case .light:
                            informationRow("Studio lighting", detail: "These controls approximate studio lights on the captured photograph using portrait coverage. Power sets the intensity and Direction moves the light. Existing shadows and reflections may remain; this is not physical lighting reconstruction or live relighting.")
                            ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(StudioLight.allCases, id: \.self) { light in Button(light.rawValue) { store.edit { $0.light = light } }.buttonStyle(.bordered).tint(store.recipe.light == light ? Palette.amber : .gray) } } }
                            if !store.hasSubject { Button("Find portrait subject") { Task { await store.analyze() } } }
                            control("Power", key: \.lightPower, range: 0...1).disabled(!store.hasSubject)
                            control("Direction", key: \.lightAngle, range: 0...1).disabled(!store.hasSubject)
                        case .adjust:
                            informationRow("Adjust", detail: "Exposure changes brightness in stops. White balance adjusts warmth, and Saturation changes colour intensity. The editing assistant uses Apple's on-device Foundation Models to suggest bounded adjustments; it does not estimate per-pixel depth.")
                            control("Exposure", key: \.exposure, range: -3...3)
                            control("White balance", key: \.temperature, range: 2500...10000)
                            control("Saturation", key: \.saturation, range: 0...2)
                            Button { showAssistant = true } label: { Label("Ask Apple Intelligence", systemImage: "sparkles") }
                        case .studio:
                            informationRow("Studio · 100 references", detail: "Choose a predefined reference or add your own. Apple Intelligence describes the setup; Image Playground creates a portrait inside Lutelier. Exact pose, lighting and identity transfer are not guaranteed. Generation may use Apple-managed Private Cloud Compute. Originals are preserved.")
                            Button { showStudio = true } label: { Label("Explore Studio", systemImage: "sparkles").font(.headline).frame(maxWidth: .infinity).padding(14).background(Palette.amber, in: Capsule()).foregroundStyle(Palette.ink) }
                        case .looks: EmptyView()
                        }
                    }.padding(.horizontal, 4)
                }
            }
        }.padding(14).lutelierGlass()
    }
    private var depthEngineControls: some View {
        HStack {
            Label("V2 Small", systemImage: "cpu").font(.caption.weight(.bold)).foregroundStyle(Palette.amber)
            Spacer()
            if store.hasDepth { Image(systemName: "checkmark.circle").accessibilityLabel("Depth ready") }
            Button("Analyze") { Task { await store.analyze() } }.font(.caption.weight(.semibold)).disabled(store.busy)
            informationButton("Depth models", detail: "Depth Anything V2 Small estimates relative depth through Core ML on the iPhone. Captured and saved depth take priority; Apple portrait/hair mattes protect coverage separately. No computer or inference server is used.\n\n\(store.depthStatus)\n\nDepth Pro: community Core ML conversions exist, but Apple's original weight license limits use to non-commercial scientific research and explicitly excludes product development. It is not installed or enabled in this app. Experimental status does not change those terms. An appropriately licensed model and physical-device validation are needed before adding it to Lutelier.", source: URL(string: "https://huggingface.co/apple/DepthPro/blob/main/LICENSE"))
        }
    }
    private func informationButton(_ title: String, detail: String, source: URL? = nil) -> some View {
        Button { information = EditorInformation(title: title, detail: detail, source: source) } label: {
            Image(systemName: "info.circle").font(.system(size: 17)).frame(width: 32, height: 32)
        }.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Information about \(title)")
    }
    private func informationRow(_ title: String, detail: String) -> some View {
        HStack { Text(title).font(.caption.weight(.semibold)); Spacer(); informationButton(title, detail: detail) }
    }
    private var lookControls: some View {
        VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(["All"] + Array(Set(store.looks.map(\.category))).filter { $0 != "All" }.sorted(), id: \.self) { item in
                        Button(item) { category = item }.font(.caption.weight(category == item ? .bold : .regular)).padding(.horizontal, 12).padding(.vertical, 8)
                            .background(category == item ? Palette.amber.opacity(0.18) : .white.opacity(0.06), in: Capsule())
                            .foregroundStyle(category == item ? Palette.amber : .secondary)
                    }
                }
            }.frame(height: 34)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(filteredLooks) { look in
                        Button { selectLook(look) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Group {
                                    if let image = store.thumbnails[look.id] { Image(uiImage: image).resizable().scaledToFill() }
                                    else { Rectangle().fill(.white.opacity(0.08)).overlay { ProgressView().scaleEffect(0.6) } }
                                }.frame(width: 78, height: 76).clipped().clipShape(.rect(cornerRadius: 12))
                                    .overlay { RoundedRectangle(cornerRadius: 12).stroke(store.recipe.lookID == look.id ? Palette.amber : .clear, lineWidth: 2) }
                                Text(look.name).font(.system(size: 10, weight: .medium)).lineLimit(1).frame(width: 78, alignment: .leading)
                            }
                        }.buttonStyle(.plain).task(id: store.selectedPhotoID) { await store.thumbnail(look) }.accessibilityLabel("Apply \(look.name). \(look.description)")
                    }
                }.padding(2)
            }
            Spacer(minLength: 0)
            GlassStrengthSlider(value: store.slider(\.strength), onEditingChanged: { if $0 { store.beginSlider() } else { store.endSlider() } })
        }
    }
    private func control(_ name: String, key: WritableKeyPath<Recipe, Double>, range: ClosedRange<Double>) -> some View {
        VStack(spacing: 3) {
            HStack { Text(name); Spacer(); Text(store.recipe[keyPath: key], format: .number.precision(.fractionLength(key == \.temperature ? 0 : 2))).monospacedDigit().foregroundStyle(.secondary) }.font(.caption)
            Slider(value: store.slider(key), in: range, onEditingChanged: { if $0 { store.beginSlider() } else { store.endSlider() } }).accessibilityLabel(name)
        }
    }
    private func grainPreset(_ name: String, amount: Double, size: Double) -> some View { Button(name) { store.edit { $0.grain = amount; $0.grainSize = size } }.buttonStyle(.bordered).font(.caption) }

    private var library: some View {
        NavigationStack {
            ScrollView {
                if store.photos.isEmpty { ContentUnavailableView("Your photographs live here", systemImage: "photo.stack", description: Text("Import a photograph or take one with the camera.")) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 12) {
                    ForEach(store.photos) { photo in Button { showLibrary = false; Task { await store.open(photo) } } label: {
                        if let image = store.libraryThumbnail(photo) { Image(uiImage: image).resizable().scaledToFill().frame(height: 145).clipped().clipShape(.rect(cornerRadius: 16)).overlay(alignment: .topLeading) { if photo.isAIGenerated == true { Text("AI GENERATED").font(.system(size: 8, weight: .semibold)).tracking(1).padding(7).background(.ultraThinMaterial, in: Capsule()).padding(7) } } }
                    }.buttonStyle(.plain) }
                }.padding()
            }.background(Palette.ink).navigationTitle("Your photographs").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showLibrary = false } } }
        }.preferredColorScheme(.dark)
    }
    private var assistant: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(Palette.amber)
                Text("Describe the feeling.").font(.largeTitle.weight(.medium))
                Text(AssistantService.status).font(.caption).foregroundStyle(.secondary)
                TextField("Warm sunset, subtle grain, softer background…", text: $store.assistantPrompt, axis: .vertical).lineLimit(3...6).padding().background(.thinMaterial, in: .rect(cornerRadius: 20))
                Button { Task { await store.askAssistant() } } label: { HStack { if store.assistantBusy { ProgressView() }; Text("Suggest an edit").font(.headline) }.frame(maxWidth: .infinity).padding(16).background(Palette.amber, in: Capsule()).foregroundStyle(Palette.ink) }.disabled(store.assistantBusy)
                Text("Suggestions use your instructions and editing settings. Use Depth to analyze or refine portrait edges.").font(.footnote).foregroundStyle(.secondary)
                Spacer()
            }.padding(24).background(Palette.ink).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showAssistant = false } } }
        }.preferredColorScheme(.dark).presentationDetents([.large])
    }
}
