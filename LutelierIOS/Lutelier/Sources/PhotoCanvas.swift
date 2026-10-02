import SwiftUI
import UIKit

private final class PhotoScrollView: UIScrollView {
    var layoutPhoto: (() -> Void)?
    override func layoutSubviews() { super.layoutSubviews(); layoutPhoto?() }
}

struct ZoomPhoto: UIViewRepresentable {
    let image: UIImage
    @Binding var visibleRegion: CGRect
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIScrollView {
        let scroll = PhotoScrollView()
        scroll.delegate = context.coordinator
        scroll.clipsToBounds = true
        scroll.bounces = false; scroll.bouncesZoom = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.layoutPhoto = { [weak scroll, weak coordinator = context.coordinator] in
            if let scroll { coordinator?.layout(scroll) }
        }
        scroll.minimumZoomScale = 1; scroll.maximumZoomScale = 8
        scroll.showsHorizontalScrollIndicator = false; scroll.showsVerticalScrollIndicator = false
        let view = context.coordinator.imageView
        view.contentMode = .scaleAspectFit; view.image = image
        scroll.addSubview(view)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        tap.numberOfTapsRequired = 2; scroll.addGestureRecognizer(tap)
        return scroll
    }
    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.imageView.image !== image {
            if UIAccessibility.isReduceMotionEnabled { context.coordinator.imageView.image = image }
            else { UIView.transition(with: context.coordinator.imageView, duration: 0.36, options: [.transitionCrossDissolve, .allowAnimatedContent, .beginFromCurrentState]) { context.coordinator.imageView.image = image } }
        }
        context.coordinator.layout(scroll)
    }
    class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ZoomPhoto
        let imageView = UIImageView()
        private var viewport = CGSize.zero
        private var imageSize = CGSize.zero
        private var layingOut = false
        init(_ parent: ZoomPhoto) { self.parent = parent }
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
        func scrollViewDidZoom(_ scroll: UIScrollView) { updateRegion(scroll) }
        func scrollViewDidScroll(_ scroll: UIScrollView) { updateRegion(scroll) }
        func layout(_ scroll: UIScrollView) {
            let size = parent.image.size, bounds = scroll.bounds.size
            guard !layingOut, bounds.width > 0, bounds.height > 0,
                  size.width > 0, size.height > 0,
                  bounds != viewport || size != imageSize else { return }
            layingOut = true
            let oldBounds = imageView.bounds
            let point = imageView.convert(CGPoint(x: scroll.contentOffset.x + viewport.width / 2, y: scroll.contentOffset.y + viewport.height / 2), from: scroll)
            let center = oldBounds.width > 0 && oldBounds.height > 0
                ? CGPoint(x: point.x / oldBounds.width, y: point.y / oldBounds.height)
                : CGPoint(x: 0.5, y: 0.5)
            let zoom = scroll.zoomScale
            viewport = bounds; imageSize = size
            scroll.setZoomScale(1, animated: false)
            // Aspect-fill creates real scrollable content at 1x when the frame crops.
            let scale = max(bounds.width / size.width, bounds.height / size.height)
            let fitted = CGSize(width: size.width * scale, height: size.height * scale)
            imageView.frame = CGRect(origin: .zero, size: fitted)
            scroll.contentSize = fitted
            scroll.setZoomScale(zoom, animated: false)
            let content = scroll.contentSize
            scroll.contentOffset = CGPoint(
                x: min(max(center.x * content.width - bounds.width / 2, 0), max(content.width - bounds.width, 0)),
                y: min(max(center.y * content.height - bounds.height / 2, 0), max(content.height - bounds.height, 0)))
            layingOut = false
            updateRegion(scroll)
        }
        func updateRegion(_ scroll: UIScrollView) {
            guard !layingOut else { return }
            let rect = scroll.convert(scroll.bounds, to: imageView).intersection(imageView.bounds)
            guard !rect.isNull, imageView.bounds.width > 0, imageView.bounds.height > 0 else { return }
            let region = CGRect(x: rect.minX / imageView.bounds.width, y: rect.minY / imageView.bounds.height, width: rect.width / imageView.bounds.width, height: rect.height / imageView.bounds.height)
            if parent.visibleRegion != region { DispatchQueue.main.async { self.parent.visibleRegion = region } }
        }
        @objc func doubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scroll = gesture.view as? UIScrollView else { return }
            if scroll.zoomScale > 1 { scroll.setZoomScale(1, animated: true) }
            else {
                let p = gesture.location(in: imageView)
                let width = scroll.bounds.width / 3, height = scroll.bounds.height / 3
                scroll.zoom(to: CGRect(x: p.x - width / 2, y: p.y - height / 2, width: width, height: height), animated: true)
            }
        }
    }
}

struct DepthSelectionOverlay: View {
    let image: UIImage
    let visibleRegion: CGRect
    @Binding var selection: CGRect?
    @State private var start: CGPoint?
    @State private var drawn: CGRect?
    var body: some View {
        GeometryReader { geometry in
            // Visible-region fractions include both aspect-fill crop and pinch zoom.
            let width = geometry.size.width / max(visibleRegion.width, 0.0001)
            let height = geometry.size.height / max(visibleRegion.height, 0.0001)
            let origin = CGPoint(x: -visibleRegion.minX * width, y: -visibleRegion.minY * height)
            ZStack(alignment: .topLeading) {
                Color.clear
                if let drawn { Rectangle().fill(Palette.amber.opacity(0.12)).overlay(Rectangle().stroke(Palette.amber, lineWidth: 1.5)).frame(width: drawn.width, height: drawn.height).offset(x: drawn.minX, y: drawn.minY) }
            }.contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                if start == nil { start = value.startLocation }
                let a = start!, b = value.location
                let box = CGRect(x: min(a.x,b.x), y: min(a.y,b.y), width: abs(a.x-b.x), height: abs(a.y-b.y)).intersection(CGRect(origin: origin, size: CGSize(width: width, height: height)))
                guard !box.isNull else { return }; drawn = box
                selection = CGRect(x: (box.minX-origin.x)/width, y: (box.minY-origin.y)/height, width: box.width/width, height: box.height/height)
            }.onEnded { _ in start = nil })
            .accessibilityLabel("Draw a rectangular depth refinement region")
        }
    }
}

struct ComparisonPhoto: View {
    let before: UIImage
    let after: UIImage
    @State private var fraction = 0.5
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image(uiImage: after).resizable().scaledToFit()
                Image(uiImage: before).resizable().scaledToFit()
                    .mask(alignment: .leading) { Rectangle().frame(width: proxy.size.width * fraction) }
                Rectangle().fill(.white.opacity(0.8)).frame(width: 1).offset(x: proxy.size.width * (fraction - 0.5))
                Image(systemName: "arrow.left.and.right").font(.caption.bold()).padding(12).background(.ultraThinMaterial, in: Circle())
                    .offset(x: proxy.size.width * (fraction - 0.5))
                VStack { HStack { Text("BEFORE"); Spacer(); Text("AFTER") }.font(.caption2.weight(.semibold)).tracking(2).padding(); Spacer() }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { fraction = min(max($0.location.x / proxy.size.width, 0), 1) })
            .accessibilityElement(children: .ignore).accessibilityLabel("Before and after comparison")
            .accessibilityAdjustableAction { direction in fraction = min(max(fraction + (direction == .increment ? 0.1 : -0.1), 0), 1) }
        }
    }
}
