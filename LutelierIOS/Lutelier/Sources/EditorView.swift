import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct EditorView: View {
    @StateObject private var store = EditorStore()
    @StateObject private var studio = StudioStore()
    @StateObject private var lensMotion = LensMotion()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var glassVisible = false
    @State private var glassPosition: CGFloat = -1.08
    @State private var glassNextImage: UIImage?
    @State private var glassTilt = 24.0
    @State private var glassOpacity = 1.0
    @State private var glassImageOpacity = 0.4
    @State private var glassBlur: CGFloat = 6
    @State private var glassFrost = 1.0
    @State private var pendingLookID: String?
    @State private var lookTransition: Task<Void, Never>?
    @State private var picker: PhotosPickerItem?
    @State private var tab = ToolTab.looks
    @State private var category = "All"
    @State private var query = ""
    @State private var compare = false
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var showAssistant = false
    @State private var showStudio = false
    @State private var importLUT = false
    @State private var visibleRegion = CGRect(x: 0, y: 0, width: 1, height: 1)
    var filteredLooks: [Look] { store.looks.filter { (category == "All" || $0.category == category) && (query.isEmpty || ($0.name + " " + $0.description).localizedCaseInsensitiveContains(query)) } }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Palette.ink.ignoresSafeArea()
                if let image = store.preview {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).blur(radius: 65).opacity(0.25).clipped().ignoresSafeArea()
                }
                VStack(spacing: 14) {
                    header
                    if let image = store.preview {
                        ZStack(alignment: .bottom) {
                            if compare, let original = store.originalPreview { ComparisonPhoto(before: original, after: image) }
                            else { ZoomPhoto(image: image, visibleRegion: $visibleRegion).id(store.selectedPhotoID) }
                            HStack(spacing: 8) {
                                Text(compare ? "Slide to compare" : "Pinch to explore").font(.caption2).foregroundStyle(.secondary)
                                Spacer()
                                Text(store.currentLook.name).font(.caption.weight(.medium))
                            }.padding(12).background(.ultraThinMaterial, in: Capsule()).padding(14).allowsHitTesting(false)
                        }
                        .overlay {
                            if glassVisible {
                                GeometryReader { size in
                                    ZStack {
                                        if let glassNextImage {
                                            let fit = min(size.size.width / glassNextImage.size.width, size.size.height / glassNextImage.size.height)
                                            let zoom = max(1, max(1 / max(visibleRegion.width, 0.125), 1 / max(visibleRegion.height, 0.125)))
                                            Image(uiImage: glassNextImage).resizable().scaledToFit()
                                                .frame(width: size.size.width, height: size.size.height)
                                                .scaleEffect(zoom)
                                                .offset(x: glassNextImage.size.width * fit * zoom * (0.5 - visibleRegion.midX), y: glassNextImage.size.height * fit * zoom * (0.5 - visibleRegion.midY))
                                                .blur(radius: glassBlur).opacity(glassImageOpacity)
                                        }
                                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                                            .fill(.white.opacity(0.025))
                                            .glassEffect(.clear, in: .rect(cornerRadius: 24))
                                            .overlay { RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.45), lineWidth: 0.7) }
                                            .opacity(glassFrost)
                                    }
                                        .frame(width: size.size.width, height: size.size.height).clipShape(.rect(cornerRadius: 24))
                                        .rotation3DEffect(.degrees(glassTilt), axis: (x: 0, y: 1, z: 0), perspective: 0.65)
                                        .rotation3DEffect(.degrees(glassTilt * 0.38), axis: (x: 1, y: 0, z: 0), perspective: 0.65)
                                        .rotationEffect(.degrees(-glassTilt * 0.25))
                                        .scaleEffect(1 + glassTilt / 960)
                                        .offset(x: size.size.width * glassPosition)
                                        .offset(y: size.size.height * glassPosition * -0.1)
                                        .shadow(color: .black.opacity(0.3), radius: glassTilt * 0.5, y: glassTilt * 0.4)
                                        .opacity(glassOpacity)
                                }.allowsHitTesting(false).accessibilityHidden(true)
                            }
                        }.clipShape(.rect(cornerRadius: 24))
                    } else { welcome }
                    if store.hasPhoto { inspector.frame(height: min(geometry.size.height * 0.36, 320)) }
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
        .onChange(of: store.selectedPhotoID) { _, _ in cancelLookTransition() }
        .onChange(of: store.error) { _, error in if error != nil { cancelLookTransition() } }
        .task(id: picker) { if let picker { await store.importPhoto(picker) } }
        .sheet(isPresented: $showCamera) { CaptureView { result in showCamera = false; Task { await store.receiveCapture(result) } } }
        .sheet(isPresented: $showLibrary) { library }
        .sheet(isPresented: $showAssistant) { assistant }
        .sheet(isPresented: $showStudio) { StudioView(editor: store, studio: studio) }
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
                Text("THE ART OF A PHOTOGRAPH").font(.system(size: 8, weight: .medium)).tracking(2).foregroundStyle(.secondary)
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

    private func cancelLookTransition() {
        lookTransition?.cancel(); pendingLookID = nil; glassVisible = false; glassPosition = -1.16; glassNextImage = nil
    }
    private func selectLook(_ look: Look) {
        guard look.id != store.recipe.lookID || pendingLookID != nil else { return }
        cancelLookTransition()
        guard !reduceMotion else { store.select(look); return }
        pendingLookID = look.id
        let photoID = store.selectedPhotoID
        let startingRecipe = store.recipe
        lookTransition = Task { @MainActor in
            do {
                let prepared = try await store.prepareLook(look)
                try Task.checkCancellation()
                guard store.selectedPhotoID == photoID, pendingLookID == look.id else { return }
                guard store.recipe == startingRecipe else { cancelLookTransition(); return }
                glassNextImage = prepared.image; glassPosition = -1.16; glassTilt = 24
                glassOpacity = 1; glassImageOpacity = 0.4; glassBlur = 6; glassFrost = 1; glassVisible = true
                try await Task.sleep(for: .milliseconds(16))
                withAnimation(.easeInOut(duration: 0.6)) { glassPosition = 0; glassTilt = 0; glassImageOpacity = 0.88 }
                try await Task.sleep(for: .milliseconds(620))
                try Task.checkCancellation()
                withAnimation(.easeInOut(duration: 0.4)) { glassBlur = 0; glassImageOpacity = 1; glassFrost = 0 }
                try await Task.sleep(for: .milliseconds(410))
                try Task.checkCancellation()
                guard store.recipe == startingRecipe else { cancelLookTransition(); return }
                store.applyPreparedLook(image: prepared.image, recipe: prepared.recipe)
                if store.renderedLookID == look.id { finishLookTransition() }
            } catch is CancellationError {} catch { cancelLookTransition(); store.error = error.localizedDescription }
        }
    }
    private func finishLookTransition() {
        guard pendingLookID != nil else { return }
        lookTransition?.cancel()
        lookTransition = Task { @MainActor in
            do {
                withAnimation(.easeInOut(duration: 0.2)) { glassOpacity = 0 }
                try await Task.sleep(for: .milliseconds(220))
                try Task.checkCancellation()
                glassVisible = false; pendingLookID = nil; glassNextImage = nil
            } catch {}
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 14) {
            HStack {
            Button { showLibrary = true } label: { Image(systemName: "square.grid.2x2").frame(width: 44, height: 44) }.accessibilityLabel("Photo library")
            PhotosPicker(selection: $picker, matching: .images, photoLibrary: .shared()) { Image(systemName: "photo.badge.plus").frame(width: 44, height: 44) }.accessibilityLabel("Import photo")
            Spacer(minLength: 0)
            if store.hasPhoto {
                Button { withAnimation(.easeInOut(duration: 0.2)) { compare.toggle() } } label: { Image(systemName: "rectangle.lefthalf.inset.filled").frame(width: 44, height: 44).foregroundStyle(compare ? Palette.amber : .white) }.accessibilityLabel("Compare original and edit")
                Button { Task { await store.export() } } label: { Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44).background(Palette.amber, in: Circle()).foregroundStyle(Palette.ink) }.disabled(store.busy).accessibilityLabel("Save edit to Photos")
            }
            }.padding(6).glassEffect(.regular, in: .rect(cornerRadius: 34, style: .continuous))
            Button { showCamera = true } label: {
                LensLogo(motion: lensMotion, size: 68)
            }.buttonStyle(CameraLensPressStyle()).accessibilityLabel("Capture")
        }.foregroundStyle(.white).buttonStyle(.plain)
    }

    private var inspector: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 4) {
                ForEach(ToolTab.allCases, id: \.self) { item in
                    Button { tab = item } label: {
                        Text(item.rawValue).font(.caption.weight(.semibold)).padding(.horizontal, 13).padding(.vertical, 11)
                            .background(tab == item ? .white.opacity(0.12) : .clear, in: Capsule())
                            .foregroundStyle(tab == item ? Palette.amber : .secondary)
                    }.buttonStyle(.plain)
                }
            } }
            if tab == .looks { lookControls }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        switch tab {
                        case .grain:
                            Text("A texture you can feel").font(.headline)
                            HStack { grainPreset("Clean", amount: 0, size: 1); grainPreset("35mm", amount: 0.3, size: 1); grainPreset("Pushed", amount: 0.65, size: 1.5) }
                            control("Grain", key: \.grain, range: 0...1)
                            control("Size", key: \.grainSize, range: 0.5...3)
                            control("Colour", key: \.grainColor, range: 0...1)
                            control("Texture", key: \.texture, range: -1...1)
                            control("Glow", key: \.glow, range: 0...1)
                            control("Halation", key: \.halation, range: 0...1)
                            control("Vignette", key: \.vignette, range: 0...1)
                        case .depth:
                            Text(store.depthStatus).font(.caption).foregroundStyle(.secondary)
                            Button("Analyze portrait") { Task { await store.analyze() } }.disabled(store.busy)
                            Picker("Bokeh", selection: Binding(get: { store.recipe.bokeh }, set: { value in store.edit { $0.bokeh = value } })) { ForEach(Bokeh.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                            control("Far blur", key: \.farBlur, range: 0...1).disabled(!store.hasSubject && !store.hasDepth)
                            control("Near blur", key: \.nearBlur, range: 0...1).disabled(!store.hasDepth)
                            control("Focus plane", key: \.focusDepth, range: 0...1).disabled(!store.hasDepth)
                            Button { Task { await store.refine(normalized: visibleRegion) } } label: { Label("Refine visible portrait edges", systemImage: "viewfinder") }.disabled(!store.hasSubject || store.busy || visibleRegion.width > 0.8)
                            Text("Pinch to zoom into hair or an edge, then refine. Portrait masks estimate subject boundaries; captured depth enables separate near and far planes.").font(.caption2).foregroundStyle(.secondary)
                        case .light:
                            Text("Your pocket studio").font(.headline)
                            ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(StudioLight.allCases, id: \.self) { light in Button(light.rawValue) { store.edit { $0.light = light } }.buttonStyle(.bordered).tint(store.recipe.light == light ? Palette.amber : .gray) } } }
                            if !store.hasSubject { Button("Find portrait subject") { Task { await store.analyze() } } }
                            control("Power", key: \.lightPower, range: 0...1).disabled(!store.hasSubject)
                            control("Direction", key: \.lightAngle, range: 0...1).disabled(!store.hasSubject)
                            Text("Studio-light approximation on the captured photo. Existing shadows and reflections may remain.").font(.caption2).foregroundStyle(.secondary)
                        case .adjust:
                            control("Exposure", key: \.exposure, range: -3...3)
                            control("White balance", key: \.temperature, range: 2500...10000)
                            control("Saturation", key: \.saturation, range: 0...2)
                            Button { showAssistant = true } label: { Label("Ask Apple Intelligence", systemImage: "sparkles") }
                        case .studio:
                            HStack {
                                Image(systemName: "camera.aperture").font(.title).foregroundStyle(Palette.amber)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Your next studio session").font(.headline)
                                    Text("100 references. A new pose, light and backdrop.").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Button { showStudio = true } label: { Label("Explore Studio", systemImage: "sparkles").font(.headline).frame(maxWidth: .infinity).padding(14).background(Palette.amber, in: Capsule()).foregroundStyle(Palette.ink) }
                            Text("Use a predefined reference or add your own. Apple Intelligence reads the setup; Image Playground creates your portrait inside Lutelier.").font(.caption2).foregroundStyle(.secondary)
                        case .looks: EmptyView()
                        }
                    }.padding(.horizontal, 4)
                }
            }
        }.padding(14).lutelierGlass()
    }
    private var lookControls: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search film, camera, or mood", text: $query).font(.caption)
                Menu { ForEach(["All"] + Array(Set(store.looks.map(\.category))).filter { $0 != "All" }.sorted(), id: \.self) { item in Button(item) { category = item } } } label: { Text(category).font(.caption).lineLimit(1); Image(systemName: "line.3.horizontal.decrease") }
            }
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
            control("Strength", key: \.strength, range: 0...1)
            Text(store.currentLook.description).font(.caption2).foregroundStyle(.secondary).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
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
