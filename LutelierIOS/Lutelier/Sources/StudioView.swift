import SwiftUI
import PhotosUI
import ImagePlayground

struct StudioView: View {
    @ObservedObject var editor: EditorStore
    @ObservedObject var studio: StudioStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.supportsImageGeneration) private var supportsImageGeneration
    @State private var customPicker: PhotosPickerItem?
    @State private var showingPlayground = false
    @State private var showRename = false
    @State private var customName = ""
    @State private var saving = false
    private var options: ImagePlaygroundOptions {
        var options = ImagePlaygroundOptions()
        options.sizeSpecification = .closest(to: studio.sourceSnapshot?.size ?? CGSize(width: 768, height: 1024))
        return options
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.ink.ignoresSafeArea()
                if studio.generatedImage != nil { resultReview }
                else { catalog }
            }
            .navigationTitle("Studio").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Text("\(studio.templates.filter { !$0.isCustom }.count) REFERENCES").font(.system(size: 9, weight: .medium)).tracking(1.5).foregroundStyle(.secondary) }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .tint(Palette.amber).scrollIndicators(.hidden).preferredColorScheme(.dark)
        .task(id: customPicker) { if let customPicker { await studio.importReference(customPicker) } }
        .onDisappear { studio.cancelAnalysis() }
        .imagePlaygroundSheet(isPresented: $showingPlayground,
            concepts: [.text(studio.request?.prompt ?? "")],
            sourceImage: studio.sourceSnapshot.map { Image(uiImage: $0) },
            onCompletion: { url in studio.receiveGenerated(url); showingPlayground = false },
            onCancellation: { showingPlayground = false })
        .imagePlaygroundGenerationStyle(.any, in: [.any])
        .imagePlaygroundOptions(options)
        .alert("Studio", isPresented: Binding(get: { studio.error != nil }, set: { if !$0 { studio.error = nil } })) {
            Button("OK") { studio.error = nil }
        } message: { Text(studio.error ?? "") }
        .alert("Name your template", isPresented: $showRename) {
            TextField("Template name", text: $customName)
            Button("Save") { studio.renameSelected(customName) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var catalog: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("A whole new\npoint of view.").font(.system(size: 36, weight: .medium, design: .default))
                    Text("Borrow the light, the pose, the atmosphere.\nKeep the photograph personal.").font(.subheadline).foregroundStyle(.secondary)
                }.padding(.top, 8)
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search studio references", text: $studio.query)
                    PhotosPicker(selection: $customPicker, matching: .images) { Image(systemName: "plus").frame(width: 36, height: 36).background(Palette.amber, in: Circle()).foregroundStyle(Palette.ink) }.accessibilityLabel("Add custom studio reference")
                }.font(.subheadline).padding(12).lutelierGlass()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack { ForEach(studio.categories, id: \.self) { category in
                        Button(category) { studio.category = category }.font(.caption.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 10)
                            .background(studio.category == category ? Palette.amber : .white.opacity(0.06), in: Capsule())
                            .foregroundStyle(studio.category == category ? Palette.ink : .white)
                    } }.buttonStyle(.plain)
                }
                if let selected = studio.selected { selectedReference(selected) }
                if studio.filtered.isEmpty {
                    ContentUnavailableView("No references here yet", systemImage: "photo.on.rectangle", description: Text("Try a different search or add your own studio photograph."))
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 16) {
                    ForEach(studio.filtered) { template in
                        Button { studio.select(template) } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                StudioThumbnail(studio: studio, template: template)
                                    .frame(height: 145).clipShape(.rect(cornerRadius: 16))
                                    .overlay { RoundedRectangle(cornerRadius: 16).stroke(studio.selectedID == template.id ? Palette.amber : .clear, lineWidth: 2) }
                                Text(template.name).font(.caption.weight(.medium)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                Text(template.category).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }.buttonStyle(.plain).accessibilityLabel("Select \(template.name)")
                    }
                }
                Text("Reference photographs include creator credits and license links. They guide the visual setup; their subjects are not used as the identity source.").font(.caption2).foregroundStyle(.secondary)
            }.padding(20)
        }
    }

    private func selectedReference(_ template: StudioTemplate) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                if let image = studio.image(template) { Image(uiImage: image).resizable().scaledToFit().frame(width: 112, height: 155).clipShape(.rect(cornerRadius: 14)) }
                VStack(alignment: .leading, spacing: 8) {
                    Text(template.name).font(.headline)
                    Text(template.category).font(.caption).foregroundStyle(Palette.amber)
                    Text(studio.status).font(.caption).foregroundStyle(.secondary)
                    if template.isCustom {
                        HStack {
                            Button { customName = template.name; showRename = true } label: { Image(systemName: "pencil") }.accessibilityLabel("Rename template")
                            Button(role: .destructive) { studio.deleteSelected() } label: { Image(systemName: "trash") }.accessibilityLabel("Delete custom template")
                        }
                    }
                }
            }
            Button(action: studio.analyze) {
                HStack { if studio.analyzing { ProgressView() }; Label(studio.analyzing ? "Analyzing reference…" : "Understand this reference", systemImage: "sparkles") }.font(.subheadline.weight(.medium))
            }.disabled(studio.analyzing)
            TextField("Describe lighting, background, pose and framing…", text: $studio.prompt, axis: .vertical)
                .lineLimit(4...12).font(.subheadline).padding(14).background(.white.opacity(0.05), in: .rect(cornerRadius: 16))
            Text("RECREATE").font(.system(size: 9, weight: .semibold)).tracking(2).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                Toggle("Pose", isOn: $studio.changePose)
                Toggle("Lighting", isOn: $studio.changeLighting)
                Toggle("Background", isOn: $studio.changeBackground)
                Toggle("Framing", isOn: $studio.changeFraming)
            }.font(.caption)
            Button(action: generate) {
                Label("Create my studio portrait", systemImage: "camera.aperture").font(.headline).frame(maxWidth: .infinity).padding(16).background(Palette.amber, in: Capsule()).foregroundStyle(Palette.ink)
            }.disabled(!supportsImageGeneration || studio.analyzing || studio.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !editor.hasPhoto)
            if !supportsImageGeneration { Text("Image generation is unavailable on this device or in its current Apple Intelligence settings.").font(.caption).foregroundStyle(.secondary) }
            Text("Creates a new image in Image Playground inside Lutelier. Apple may process generation on Private Cloud Compute. Pose, identity and reference matching can vary; review the result before keeping it.").font(.caption2).foregroundStyle(.secondary)
            DisclosureGroup("Photo credits") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(template.sourceTitle).font(.caption2)
                    Text("Photo: \(template.author)").font(.caption)
                    Text(template.license).font(.caption2).foregroundStyle(.secondary)
                    if let url = URL(string: template.sourceURL), !template.sourceURL.isEmpty { Link("Original photo & attribution", destination: url) }
                    if let url = URL(string: template.licenseURL), !template.licenseURL.isEmpty { Link("Photo license", destination: url) }
                    if let modification = template.modification { Text(modification).font(.caption2).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
            }.font(.caption)
        }.padding(18).lutelierGlass()
    }

    private func generate() {
        guard supportsImageGeneration, let id = editor.selectedPhotoID, let source = editor.originalPreview else { return }
        do {
            try studio.prepare(sourcePhotoID: id, source: source)
            showingPlayground = true
        } catch { studio.error = error.localizedDescription }
    }

    private var resultReview: some View {
        VStack(spacing: 18) {
            Text("Your studio portrait").font(.system(size: 28, weight: .medium, design: .default))
            if let result = studio.generatedImage, let source = studio.sourceSnapshot {
                ComparisonPhoto(before: source, after: result).clipShape(.rect(cornerRadius: 24))
            }
            Text("AI GENERATED · Slide to compare with your source").font(.caption2).foregroundStyle(.secondary)
            HStack {
                Button("Try again") { studio.clearResult(); showingPlayground = true }.buttonStyle(.bordered).disabled(saving)
                Button {
                    guard let data = studio.generatedData, let request = studio.request else { return }
                    saving = true
                    Task {
                        let success = await editor.receiveStudioResult(data, request: request)
                        saving = false
                        if success { studio.clearResult(); dismiss() }
                        else { studio.error = editor.error; editor.error = nil }
                    }
                } label: { HStack { if saving { ProgressView() }; Text("Keep portrait") }.font(.headline).padding(.horizontal, 20).padding(.vertical, 14).background(Palette.amber, in: Capsule()).foregroundStyle(Palette.ink) }.disabled(saving)
            }
            Button("Discard result", role: .destructive) { studio.clearResult() }.font(.caption).disabled(saving)
            Text("Keeping saves a separate photograph to your Lutelier library. Your source remains untouched; export the result to Photos when ready.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(20)
    }
}

private struct StudioThumbnail: View {
    let studio: StudioStore
    let template: StudioTemplate
    @State private var image: UIImage?
    var body: some View {
        Group { if let image { Image(uiImage: image).resizable().scaledToFill() } else { Rectangle().fill(.white.opacity(0.07)).overlay { ProgressView() } } }
            .clipped().task(id: template.id) { image = studio.image(template, maximum: 280) }
    }
}
