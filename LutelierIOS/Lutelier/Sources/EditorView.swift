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

private struct DepthDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { configuration.isExpanded.toggle() } label: {
                HStack {
                    configuration.label
                    Spacer(minLength: 8)
                    Image(systemName: configuration.isExpanded ? "chevron.up" : "chevron.down").font(.caption.weight(.semibold))
                }.frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
            if configuration.isExpanded { configuration.content }
        }
    }
}

struct EditorView: View {
    @Namespace private var toolSelection
    @Namespace private var chrome
    @State private var tabFrames: [ToolTab: CGRect] = [:]
    @GestureState private var hoveredTab: ToolTab?
    @StateObject private var store: EditorStore
    @StateObject private var studio = StudioStore()
    @StateObject private var lensMotion = LensMotion()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var analysisTexture = AnalysisTexture.photo
    @State private var selectingDepth = false
    @State private var showingDepthRefinement = false
    @State private var depthSelection: CGRect?
    @State private var pendingLookID: String?
    @State private var lookTransition: Task<Void, Never>?
    @State private var picker: PhotosPickerItem?
    @State private var tab = ToolTab.looks
    @State private var depthSection = "Setup"
    @State private var adjustSection = "Colour"
    @State private var category = "All"
    @State private var compare = false
    @State private var expandedPhoto = false
    @State private var comparisonFraction: CGFloat = 0.5
    @State private var imageFrame = CGRect.zero
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var showAssistant = false
    @State private var showStudio = false
    @State private var importLUT = false
    @State private var information: EditorInformation?
    @State private var visibleRegion = CGRect(x: 0, y: 0, width: 1, height: 1)
    @MainActor init(store: EditorStore? = nil, expandedPhoto: Bool = false, comparing: Bool = false, initialTab: ToolTab = .looks, initialDepthSection: String = "Setup") {
        _store = StateObject(wrappedValue: store ?? EditorStore())
        _expandedPhoto = State(initialValue: expandedPhoto)
        _compare = State(initialValue: comparing)
        _tab = State(initialValue: initialTab)
        _depthSection = State(initialValue: initialDepthSection)
    }
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
                VStack(spacing: expandedPhoto ? 8 : 12) {
                    if !expandedPhoto { header }
                    if let image = store.preview {
                        photoStage(image)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .layoutPriority(1)
                    } else { welcome }
                    if store.hasPhoto && !expandedPhoto {
                        inspector.frame(height: min(geometry.size.height * (tab == .looks ? 0.42 : 0.34), tab == .looks ? 252 : 232))
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    if expandedPhoto {
                        if tab == .looks && !compare { expandedLooks } else { expandedToolbar }
                    } else { bottomBar }
                }.padding(.horizontal, expandedPhoto ? 6 : 16).padding(.vertical, 8)
                if store.busy && !store.analysisRunning { ProgressView().padding(22).lutelierGlass().accessibilityLabel("Processing photograph") }
            }
        }
        .tint(Palette.amber).preferredColorScheme(.dark).buttonStyle(.glass)
        .scrollIndicators(.hidden)
        .onAppear { if !reduceMotion { lensMotion.start() } }
        .onDisappear { lensMotion.stop(); lookTransition?.cancel() }
        .onChange(of: scenePhase) { _, phase in if phase == .active && !reduceMotion { lensMotion.start() } else { lensMotion.stop() } }
        .onChange(of: reduceMotion) { _, reduced in if reduced { lensMotion.stop(); cancelLookTransition() } else if scenePhase == .active { lensMotion.start() } }
        .onChange(of: store.renderedLookID) { _, value in if value == pendingLookID { finishLookTransition() } }
        .onChange(of: store.selectedPhotoID) { _, _ in cancelLookTransition(); depthSelection = nil; selectingDepth = false; analysisTexture = .photo; compare = false; comparisonFraction = 0.5 }
        .onChange(of: tab) { _, value in if value != .depth { selectingDepth = false; analysisTexture = .photo } }
        .onChange(of: showingDepthRefinement) { _, expanded in if !expanded { selectingDepth = false } }
        .onChange(of: store.hasDepth) { _, available in if !available { selectingDepth = false; depthSelection = nil; if analysisTexture == .depth { analysisTexture = .photo } } }
        .onChange(of: store.error) { _, error in if error != nil { cancelLookTransition() } }
        .task(id: picker) { if let picker { await store.importPhoto(picker) } }
        .sheet(isPresented: $showCamera) { CaptureView(onImport: { item in showCamera = false; Task { await store.importPhoto(item) } }) { result in showCamera = false; Task { await store.receiveCapture(result) } } }
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

    private func toggleExpanded() {
        selectingDepth = false
        withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86)) { expandedPhoto.toggle(); if !expandedPhoto { compare = false } }
    }

    private func toggleComparison() {
        selectingDepth = false
        analysisTexture = .photo
        withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86)) {
            compare.toggle()
            if compare { expandedPhoto = true }
        }
    }

    private func photoStage(_ image: UIImage) -> some View {
        ZStack {
            GeometryReader { geometry in
                let visible = imageFrame.intersection(CGRect(origin: .zero, size: geometry.size))
                if !visible.isNull && visible.width > 0 {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: visible.width, height: visible.height).clipped()
                        .clipShape(.rect(cornerRadius: 28)).blur(radius: 30)
                        .scaleEffect(1.08).opacity(0.7)
                        .offset(x: visible.minX + (reduceMotion ? 0 : lensMotion.x * 1.5), y: visible.minY + (reduceMotion ? 0 : (lensMotion.y - 6) * 1.5))
                }
            }.allowsHitTesting(false).accessibilityHidden(true)
            ZoomPhoto(image: analysisTexture == .depth ? (store.depthPreview ?? image) : analysisTexture == .portrait ? (store.portraitPreview ?? image) : analysisTexture == .hair ? (store.hairPreview ?? image) : image,
                      visibleRegion: $visibleRegion, before: compare ? store.originalPreview : nil,
                      comparisonFraction: comparisonFraction, imageFrame: $imageFrame, alignLeading: false)
                .id(store.selectedPhotoID)
            if selectingDepth && store.hasDepth && !store.busy && tab == .depth && !compare {
                DepthSelectionOverlay(imageFrame: imageFrame, selection: $depthSelection)
            }
            if compare { ComparisonDivider(fraction: $comparisonFraction) }
            GeometryReader { geometry in
                let visible = imageFrame.intersection(CGRect(origin: .zero, size: geometry.size))
                if !visible.isNull && visible.width > 0 {
            VStack {
                HStack(alignment: .top) {
                    if analysisTexture != .photo {
                        Text(analysisTexture == .depth ? "Depth · white is near" : analysisTexture == .hair ? "Hair coverage" : "Portrait coverage")
                            .font(.caption).padding(10).glassEffect().allowsHitTesting(false)
                    }
                    Spacer()
                    if !compare {
                        Button(action: toggleExpanded) {
                            Image(systemName: expandedPhoto ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                .frame(width: 44, height: 44).contentTransition(.symbolEffect(.replace))
                        }.buttonStyle(ToolGlassPressStyle()).accessibilityLabel(expandedPhoto ? "Show editing tools" : "Expand photograph")
                    }
                }
                Spacer()
                if !compare && !expandedPhoto && (selectingDepth || imageFrame.height > 200) {
                    Text(selectingDepth ? "Draw a box to refine depth" : "Pinch to zoom · double-tap to reset")
                        .font(.caption2).lineLimit(1).minimumScaleFactor(0.7).padding(.horizontal, 12).padding(.vertical, 8).glassEffect().allowsHitTesting(false)
                }
            }.padding(10).frame(width: visible.width, height: visible.height).offset(x: visible.minX, y: visible.minY)
                }
            }
        }.coordinateSpace(name: "photo-stage")
    }

    private var expandedLooks: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .center, spacing: 12) {
                        ForEach(store.looks) { look in
                            let selected = store.recipe.lookID == look.id
                            Button { selectLook(look) } label: {
                                VStack(spacing: 7) {
                                    ZStack {
                                        if selected, let image = store.thumbnails[look.id] {
                                            Image(uiImage: image).resizable().scaledToFill()
                                                .frame(width: 86, height: 86).clipped().blur(radius: 18)
                                                .opacity(0.85).offset(x: reduceMotion ? 0 : lensMotion.x, y: reduceMotion ? 0 : lensMotion.y - 6)
                                        }
                                        Group {
                                            if let image = store.thumbnails[look.id] { Image(uiImage: image).resizable().scaledToFill() }
                                            else { Rectangle().fill(.white.opacity(0.1)).overlay { ProgressView() } }
                                        }.frame(width: selected ? 86 : 68, height: selected ? 86 : 68)
                                            .clipShape(.rect(cornerRadius: 18))
                                            .overlay { RoundedRectangle(cornerRadius: 18).stroke(selected ? Palette.amber : .white.opacity(0.2), lineWidth: selected ? 2 : 1) }
                                    }.frame(width: 90, height: 94)
                                    Text(look.name).font(.caption2.weight(selected ? .semibold : .regular))
                                        .foregroundStyle(selected ? Palette.amber : .white).lineLimit(1)
                                }.frame(width: 90)
                            }.buttonStyle(.plain).id(look.id)
                                .accessibilityLabel("Apply \(look.name)").accessibilityAddTraits(selected ? .isSelected : [])
                                .task(id: store.selectedPhotoID) { await store.thumbnail(look) }
                        }
                    }.padding(.horizontal, max(0, (geometry.size.width - 90) / 2)).padding(.vertical, 12)
                }.scrollClipDisabled()
                    .onAppear { proxy.scrollTo(store.recipe.lookID, anchor: .center) }
                    .onChange(of: store.recipe.lookID) { _, selected in
                        withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85)) { proxy.scrollTo(selected, anchor: .center) }
                    }
            }
        }.frame(height: 140)
    }

    private var expandedToolbar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button(action: toggleExpanded) { Label("Tools", systemImage: "slider.horizontal.3").padding(.horizontal, 14).frame(height: 48) }
                    .glassEffectID("tools", in: chrome).accessibilityLabel("Return to editing tools")
                Button(action: toggleComparison) {
                    Label("Compare", systemImage: "rectangle.lefthalf.inset.filled")
                        .font(.subheadline.weight(.medium)).padding(.horizontal, 14).frame(height: 48)
                }.glassEffectID("compare", in: chrome).accessibilityValue(compare ? "On" : "Off")
                Button { Task { await store.export() } } label: { Image(systemName: "square.and.arrow.up").frame(width: 48, height: 48) }
                    .glassEffectID("export", in: chrome).disabled(store.busy).accessibilityLabel("Save edit to Photos")
            }.glassIsland()
        }.frame(maxWidth: .infinity)
    }

    private var header: some View {
        HStack(spacing: 10) {
            photoActions
            Spacer()
            if store.hasPhoto { HStack(spacing: 0) {
                Button { cancelLookTransition(); store.undo() } label: { Image(systemName: "arrow.uturn.backward").frame(width: 44, height: 44) }.disabled(!store.canUndo).accessibilityLabel("Undo")
                Button { cancelLookTransition(); store.redo() } label: { Image(systemName: "arrow.uturn.forward").frame(width: 44, height: 44) }.disabled(!store.canRedo).accessibilityLabel("Redo")
                Menu { Button("Reset edits") { cancelLookTransition(); store.reset() }; Button("Import .cube LUT") { importLUT = true }; Button("Editing assistant") { showAssistant = true }; if store.hasLivePhoto { Button("Save Live Photo original") { Task { await store.exportLiveOriginal() } } }; if store.hasRaw { Button("Save RAW original") { Task { await store.exportRaw() } } } } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("More tools")
            }.glassIsland() }
        }.frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(.white)
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
            PhotosPicker(selection: $picker, matching: .images, preferredItemEncoding: .current, photoLibrary: .shared()) { Label("Choose a photograph", systemImage: "plus").font(.headline).frame(maxWidth: .infinity).padding(18) }.buttonStyle(.glassProminent)
            Button { showCamera = true } label: { Label("Open camera", systemImage: "camera").padding(14) }
            Spacer(minLength: 0)
        }
    }
    private func feature(_ text: String, icon: String) -> some View { Label(text, systemImage: icon).font(.caption).padding(.horizontal, 14).padding(.vertical, 10).lutelierGlass() }

    private func cancelLookTransition() { lookTransition?.cancel(); pendingLookID = nil }
    private func selectLook(_ look: Look) {
        cancelLookTransition(); store.select(look)
        if !expandedPhoto {
            withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86)) { expandedPhoto = true }
        }
    }
    private func finishLookTransition() { pendingLookID = nil }

    private var photoActions: some View {
        HStack(spacing: 0) {
                    Button { showLibrary = true } label: { Image(systemName: "square.grid.2x2").frame(width: 44, height: 44) }.accessibilityLabel("Photo library")
                    PhotosPicker(selection: $picker, matching: .images, preferredItemEncoding: .current, photoLibrary: .shared()) { Image(systemName: "photo.badge.plus").frame(width: 44, height: 44) }.accessibilityLabel("Import photo")
                    if store.hasPhoto {
                        Button(action: toggleComparison) { Image(systemName: "rectangle.lefthalf.inset.filled").frame(width: 44, height: 44) }.accessibilityLabel("Compare original and edit")
                        Button { Task { await store.export() } } label: { Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44).foregroundStyle(Palette.amber) }.disabled(store.busy).accessibilityLabel("Save edit to Photos")
                    }
                }.glassIsland()
    }

    private var bottomBar: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(alignment: .bottom, spacing: 12) {
                if store.hasPhoto {
                    GeometryReader { bounds in
                        NativeToolTabs(selection: $tab)
                            .frame(width: bounds.size.width + 40, height: 58)
                            .offset(x: -20, y: 8)
                    }.frame(height: 58)
                }
                if !store.hasPhoto { Spacer(minLength: 0) }
                Button { showCamera = true } label: { LensLogo(motion: lensMotion, size: 64, castsShadow: false) }
                    .buttonStyle(CameraLensPressStyle(shadowX: lensMotion.x, shadowY: lensMotion.y)).accessibilityLabel("Capture")
            }.foregroundStyle(.white)
        }
    }

    private var inspector: some View {
        VStack(spacing: 12) {
            if tab == .looks { ScrollView { lookControls } }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        switch tab {
                        case .depth:
                            depthControls
                        case .adjust:
                            Picker("Adjust tools", selection: $adjustSection) {
                                ForEach(["Colour", "Grain", "Light"], id: \.self) { Text($0).tag($0) }
                            }.pickerStyle(.segmented)
                            switch adjustSection {
                            case "Grain": grainControls
                            case "Light": lightControls
                            default: colourControls
                            }
                        case .studio:
                            informationRow("Studio · 100 references", detail: "Choose a predefined reference or add your own. Apple Intelligence describes the setup; Image Playground creates a portrait inside Lutelier. Exact pose, lighting and identity transfer are not guaranteed. Generation may use Apple-managed Private Cloud Compute. Originals are preserved.")
                            Button { showStudio = true } label: { Label("Explore Studio", systemImage: "sparkles").font(.headline).frame(maxWidth: .infinity).padding(14) }.buttonStyle(.glassProminent)
                        case .looks: EmptyView()
                        }
                    }.padding(.horizontal, 4)
                }
            }
        }.padding(12).lutelierGlass().sensoryFeedback(.selection, trigger: tab)
    }
    private var grainControls: some View {
        VStack(alignment: .leading, spacing: 10) {
                            informationRow("Grain", detail: "Grain changes amount, size and colour of a repeatable film texture. Texture adds local contrast; Glow softens highlights; Halation adds warm highlight spill; Vignette darkens the frame edges.")
                            HStack { grainPreset("Clean", amount: 0, size: 1); grainPreset("35mm", amount: 0.3, size: 1); grainPreset("Pushed", amount: 0.65, size: 1.5) }
                            control("Grain", key: \.grain, range: 0...1)
                            control("Size", key: \.grainSize, range: 0.5...3)
                            control("Colour", key: \.grainColor, range: 0...1)
                            control("Texture", key: \.texture, range: -1...1)
                            control("Glow", key: \.glow, range: 0...1)
                            control("Halation", key: \.halation, range: 0...1)
                            control("Vignette", key: \.vignette, range: 0...1)
        }
    }
    private var lightControls: some View {
        VStack(alignment: .leading, spacing: 10) {
                            informationRow("Studio lighting", detail: "These controls approximate studio lights on the captured photograph using portrait coverage. Power sets the intensity and Direction moves the light. Existing shadows and reflections may remain; this is not physical lighting reconstruction or live relighting.")
                            ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(StudioLight.allCases, id: \.self) { light in Button(light.rawValue) { store.edit { $0.light = light } }.buttonStyle(.glass).tint(store.recipe.light == light ? Palette.amber : .gray) } } }
                            if !store.hasSubject { Button("Find portrait subject") { Task { await store.analyze() } } }
                            control("Power", key: \.lightPower, range: 0...1).disabled(!store.hasSubject)
                            control("Direction", key: \.lightAngle, range: 0...1).disabled(!store.hasSubject)
        }
    }
    private var colourControls: some View {
        VStack(alignment: .leading, spacing: 10) {
                            informationRow("Adjust", detail: "Exposure changes brightness in stops. White balance adjusts warmth, and Saturation changes colour intensity. The editing assistant uses Apple's on-device Foundation Models to suggest bounded adjustments; it does not estimate per-pixel depth.")
                            control("Exposure", key: \.exposure, range: -3...3)
                            control("White balance", key: \.temperature, range: 2500...10000)
                            control("Saturation", key: \.saturation, range: 0...2)
                            Button { showAssistant = true } label: { Label("Ask Apple Intelligence", systemImage: "sparkles") }
        }
    }
    private var depthControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Depth tools", selection: $depthSection) {
                ForEach(["Setup", "Blur", "Lens", "Refine"], id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.segmented)
            if store.analysisRunning && depthSection != "Setup" { depthEngineControls }
            switch depthSection {
            case "Setup":
                depthEngineControls
                DisclosureGroup("Portrait and maps") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("View", selection: $analysisTexture) {
                        Text("Photo").tag(AnalysisTexture.photo)
                        if store.hasDepth { Text("Depth").tag(AnalysisTexture.depth) }
                        if store.portraitPreview != nil { Text("Portrait").tag(AnalysisTexture.portrait) }
                        if store.hairPreview != nil { Text("Hair").tag(AnalysisTexture.hair) }
                    }.pickerStyle(.segmented).disabled(store.busy)
                    Text("Depth: white is near, black is far. Portrait and hair show subject coverage.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text(store.matteStatus).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button {
                        Task { await store.analyze(portraitOnly: true) }
                    } label: {
                        Label(store.hasSubject ? "Refresh portrait mask" : "Find portrait mask", systemImage: "person.crop.rectangle")
                            .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.glass).disabled(store.busy)
                    if store.hairPreview == nil {
                        Text("Hair coverage requires an embedded Apple hair matte. Capture with RAW off on a supported lens.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(.top, 10)
                }
            case "Blur":
            VStack(spacing: 10) {
                control("Far blur", key: \.farBlur, range: 0...1).disabled(!store.hasSubject && !store.hasDepth)
                control("Near blur", key: \.nearBlur, range: 0...1).disabled(!store.hasDepth)
                control("Focus plane", key: \.focusDepth, range: 0...1).disabled(!store.hasDepth)
            }.disabled(store.busy)
            if !store.hasDepth {
                Text(store.hasSubject ? "Portrait blur is ready. Analyze to add near blur and focus control." : "Analyze your photograph to enable depth blur.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            case "Lens":
                VStack(alignment: .leading, spacing: 12) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 95), spacing: 8)], spacing: 8) {
                        ForEach(Bokeh.allCases, id: \.self) { shape in
                            Button { store.edit { $0.bokeh = shape } } label: {
                                Text(shape.rawValue).font(.caption.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                                    .background(store.recipe.bokeh == shape ? Palette.amber.opacity(0.2) : .white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                                    .foregroundStyle(store.recipe.bokeh == shape ? Palette.amber : .white)
                            }.buttonStyle(.plain).accessibilityLabel("\(shape.rawValue) bokeh")
                                .accessibilityAddTraits(store.recipe.bokeh == shape ? .isSelected : [])
                        }
                    }
                    if !store.hasDepth && !store.hasSubject {
                        Text("Shape selected. Analyze depth or find a portrait, then increase Far blur to see the effect.").font(.caption).foregroundStyle(.secondary)
                    } else if store.recipe.farBlur == 0 && store.recipe.nearBlur == 0 {
                        Text("Increase Near or Far blur to see the selected lens effect.").font(.caption).foregroundStyle(.secondary)
                    }
                    if store.recipe.bokeh == .anamorphic { control("Oval ratio", key: \.anamorphicRatio, range: 1...3) }
                    if store.recipe.bokeh == .polygon {
                        Stepper("Aperture blades · \(store.recipe.apertureBlades)", value: Binding(get: { store.recipe.apertureBlades }, set: { value in store.edit { $0.apertureBlades = value } }), in: 3...9).font(.subheadline).frame(minHeight: 44)
                    }
                    control("Bokeh highlights", key: \.bokehHighlights, range: 0...1)
                    control("Cat-eye edges", key: \.catEye, range: 0...1)
                    control("Aperture rotation", key: \.apertureRotation, range: -90...90)
                    control("Background bloom", key: \.bokehBloom, range: 0...1)
                    control("Highlight sensitivity", key: \.highlightSensitivity, range: 0...1)
                    HStack {
                        Toggle("Preserve portrait edges", isOn: Binding(get: { store.recipe.protectPortraitEdges }, set: { value in store.edit { $0.protectPortraitEdges = value } })).disabled(!store.hasSubject)
                        informationButton("Portrait edges", detail: "\(store.matteStatus)\n\nProtection reduces blur on subject edges. Captured portrait and hair mattes are used when available; person segmentation is the fallback.")
                    }
                    informationRow("About lens effects", detail: "Near and Far blur act on either side of the focus plane. Anamorphic changes oval ratio; Polygon changes aperture blades. Bokeh highlights extracts bright lights. Cat-eye edges clips highlights towards the frame edges; rotation turns the aperture. Bloom softens highlight spill; sensitivity sets its luminosity threshold. These are cinematic approximations. Inspect hair and strong lights for edge halos.")
                }.padding(.top, 10).disabled(store.busy)
            default:
                VStack(alignment: .leading, spacing: 12) {
                    if store.hasDepth {
                        Toggle("Select an area", isOn: $selectingDepth)
                        Text(selectingDepth ? "Draw a box on the photograph above, then refine it." : "Turn on selection to choose an area of the photograph.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Picker("Refinement method", selection: $store.depthRefinementMethod) {
                            Text("Context").tag(DepthRefinementMethod.contextual)
                            Text("Detail tiles").tag(DepthRefinementMethod.overlapping)
                        }.pickerStyle(.segmented)
                        Text(store.depthRefinementMethod == .contextual ? "A single pass with surrounding context." : "Experimental: multiple detail passes. Takes longer and uses more memory.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button {
                            guard let region = depthSelection else { return }
                            Task { await store.refine(normalized: region) }
                        } label: {
                            Label("Refine selected area", systemImage: "viewfinder").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                        }.buttonStyle(.glass).disabled(!selectingDepth || depthSelection == nil)
                        informationRow("About refinement", detail: "Context runs one contextual inference. Detail tiles uses one context and four detail crops with scale alignment, consistency checks and feathered blending. Depth outside the box and portrait/hair coverage are preserved. Finer geometry is not guaranteed.\n\nCurrent state: \(store.depthStatus)")
                    } else {
                        Text("Analyze the photograph before refining an area.").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.top, 10).disabled(store.busy)
            }
        }.padding(.bottom, 8)
            .onChange(of: depthSection) { _, value in if value != "Refine" { selectingDepth = false } }
    }

    private var depthEngineControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Menu {
                Picker("Depth model", selection: $store.depthEngine) {
                    ForEach(DepthEngine.allCases.filter(\.isInstalled)) { Text($0.rawValue).tag($0) }
                }
            } label: {
                HStack {
                    Text(store.depthEngine.rawValue).font(.subheadline).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.caption)
                }.frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.glass).disabled(store.busy).accessibilityLabel("Depth model")
            if store.analysisRunning {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(store.depthStatus).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                    Button(store.cancellingAnalysis ? "Cancelling…" : "Cancel") { store.cancelAnalysis() }
                        .disabled(store.cancellingAnalysis).buttonStyle(.glass)
                }.frame(minHeight: 44)
            } else {
                Button {
                    selectingDepth = false; depthSelection = nil
                    Task { await store.analyze(regenerate: true) }
                } label: {
                    Label(store.hasDepth ? "Update scene depth" : "Analyze scene depth", systemImage: "viewfinder")
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.glassProminent).disabled(store.busy || !store.hasPhoto)
                Text(store.hasDepth ? "Depth ready · adjust blur in the Blur tab" : "Estimate scene depth, then choose the focus plane.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func informationButton(_ title: String, detail: String, source: URL? = nil) -> some View {
        Button { information = EditorInformation(title: title, detail: detail, source: source) } label: {
            Image(systemName: "info.circle").font(.system(size: 17)).frame(width: 44, height: 44)
        }.buttonStyle(ToolGlassPressStyle()).foregroundStyle(.secondary).accessibilityLabel("Information about \(title)")
    }
    private func informationRow(_ title: String, detail: String) -> some View {
        HStack { Text(title).font(.caption.weight(.semibold)); Spacer(); informationButton(title, detail: detail) }
    }
    private var lookControls: some View {
        VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(["All"] + Array(Set(store.looks.map(\.category))).filter { $0 != "All" }.sorted(), id: \.self) { item in
                        Button { category = item } label: {
                            Text(item).font(.caption.weight(category == item ? .bold : .regular))
                                .padding(.horizontal, 12).frame(minHeight: 44)
                                .foregroundStyle(category == item ? Palette.amber : .secondary)
                        }.buttonStyle(ToolGlassPressStyle())
                    }
                }
            }.frame(height: 44)
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
            }.frame(height: 100)
            Spacer(minLength: 0)
            GlassStrengthSlider(value: store.slider(\.strength), onEditingChanged: { if $0 { store.beginSlider() } else { store.endSlider() } })
        }
    }
    private func control(_ name: String, key: WritableKeyPath<Recipe, Double>, range: ClosedRange<Double>) -> some View {
        VStack(spacing: 3) {
            HStack { Text(name); Spacer(); Text(store.recipe[keyPath: key], format: .number.precision(.fractionLength(key == \.temperature ? 0 : 2))).monospacedDigit().foregroundStyle(.secondary) }.font(.caption)
            SnapSlider(value: store.slider(key), range: range, defaultValue: Recipe()[keyPath: key], onEditingChanged: { if $0 { store.beginSlider() } else { store.endSlider() } }).accessibilityLabel(name)
        }
    }
    private func grainPreset(_ name: String, amount: Double, size: Double) -> some View { Button(name) { store.edit { $0.grain = amount; $0.grainSize = size } }.buttonStyle(.glass).font(.caption) }

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
