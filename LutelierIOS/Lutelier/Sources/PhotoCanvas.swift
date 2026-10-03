import SwiftUI
import UIKit

private final class PhotoScrollView: UIScrollView {
    var layoutPhoto: (() -> Void)?
    override func layoutSubviews() { super.layoutSubviews(); layoutPhoto?() }
}

struct ZoomPhoto: UIViewRepresentable {
    let image: UIImage
    @Binding var visibleRegion: CGRect
    var before: UIImage? = nil
    var comparisonFraction: CGFloat = 0.5
    var alignLeading = false
    @Binding var imageFrame: CGRect
    init(image: UIImage, visibleRegion: Binding<CGRect>, before: UIImage? = nil, comparisonFraction: CGFloat = 0.5, imageFrame: Binding<CGRect> = .constant(.zero), alignLeading: Bool = false) {
        self.image = image; self._visibleRegion = visibleRegion; self.before = before
        self.alignLeading = alignLeading; self.comparisonFraction = comparisonFraction; self._imageFrame = imageFrame
    }
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
        view.addSubview(context.coordinator.beforeView)
        context.coordinator.beforeView.layer.mask = context.coordinator.comparisonMask
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
        context.coordinator.beforeView.image = before
        context.coordinator.beforeView.isHidden = before == nil
        context.coordinator.layout(scroll)
        context.coordinator.updateComparison(scroll)
    }
    class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ZoomPhoto
        let imageView = UIImageView()
        let beforeView = UIImageView()
        let comparisonMask = CALayer()
        let photoMask = CALayer()
        private var viewport = CGSize.zero
        private var imageSize = CGSize.zero
        private var layingOut = false
        init(_ parent: ZoomPhoto) { self.parent = parent; beforeView.contentMode = .scaleAspectFit; comparisonMask.backgroundColor = UIColor.white.cgColor }
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
        func scrollViewDidZoom(_ scroll: UIScrollView) { centerImage(scroll); updateRegion(scroll) }
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
            // Show the complete photograph at 1x; pinch to inspect details.
            let scale = min(bounds.width / size.width, bounds.height / size.height)
            let fitted = CGSize(width: size.width * scale, height: size.height * scale)
            imageView.frame = CGRect(origin: .zero, size: fitted)
            beforeView.frame = imageView.bounds
            scroll.contentSize = fitted
            scroll.setZoomScale(zoom, animated: false)
            centerImage(scroll)
            let content = scroll.contentSize
            scroll.contentOffset = CGPoint(
                x: min(max(center.x * content.width - bounds.width / 2, -scroll.contentInset.left), max(content.width - bounds.width + scroll.contentInset.right, -scroll.contentInset.left)),
                y: min(max(center.y * content.height - bounds.height / 2, -scroll.contentInset.top), max(content.height - bounds.height + scroll.contentInset.bottom, -scroll.contentInset.top)))
            layingOut = false
            updateRegion(scroll)
        }
        func centerImage(_ scroll: UIScrollView) {
            let horizontal = max(0, (scroll.bounds.width - scroll.contentSize.width) / 2)
            let vertical = max(0, (scroll.bounds.height - scroll.contentSize.height) / 2)
            scroll.contentInset = UIEdgeInsets(top: vertical, left: parent.alignLeading ? 0 : horizontal, bottom: vertical, right: parent.alignLeading ? horizontal * 2 : horizontal)
        }
        func updateComparison(_ scroll: UIScrollView) {
            let point = imageView.convert(CGPoint(x: scroll.bounds.minX + scroll.bounds.width * parent.comparisonFraction, y: scroll.bounds.minY), from: scroll)
            CATransaction.begin(); CATransaction.setDisableActions(true)
            beforeView.frame = imageView.bounds
            comparisonMask.frame = CGRect(x: 0, y: 0, width: min(imageView.bounds.width, max(0, point.x)), height: imageView.bounds.height)
            CATransaction.commit()
        }
        func updateRegion(_ scroll: UIScrollView) {
            guard !layingOut else { return }
            updateComparison(scroll)
            let visible = imageView.convert(imageView.bounds, to: scroll).intersection(scroll.bounds)
            CATransaction.begin(); CATransaction.setDisableActions(true)
            photoMask.backgroundColor = UIColor.white.cgColor
            photoMask.cornerCurve = .continuous
            photoMask.cornerRadius = min(28, min(visible.width, visible.height) / 2)
            photoMask.frame = visible
            scroll.layer.mask = photoMask
            CATransaction.commit()
            let frame = imageView.convert(imageView.bounds, to: scroll).offsetBy(dx: -scroll.bounds.minX, dy: -scroll.bounds.minY)
            let rect = scroll.convert(scroll.bounds, to: imageView).intersection(imageView.bounds)
            guard !rect.isNull, imageView.bounds.width > 0, imageView.bounds.height > 0 else { return }
            let region = CGRect(x: rect.minX / imageView.bounds.width, y: rect.minY / imageView.bounds.height, width: rect.width / imageView.bounds.width, height: rect.height / imageView.bounds.height)
            if parent.visibleRegion != region || parent.imageFrame != frame { DispatchQueue.main.async { self.parent.visibleRegion = region; self.parent.imageFrame = frame } }
        }
        @objc func doubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scroll = gesture.view as? UIScrollView else { return }
            if scroll.zoomScale > 1 { scroll.setZoomScale(1, animated: !UIAccessibility.isReduceMotionEnabled) }
            else {
                let p = gesture.location(in: imageView)
                let width = scroll.bounds.width / 3, height = scroll.bounds.height / 3
                scroll.zoom(to: CGRect(x: p.x - width / 2, y: p.y - height / 2, width: width, height: height), animated: !UIAccessibility.isReduceMotionEnabled)
            }
        }
    }
}

enum PhotoSelectionGeometry {
    static func normalized(_ rectangle: CGRect, imageFrame: CGRect, viewport: CGRect) -> CGRect? {
        guard imageFrame.width > 0, imageFrame.height > 0 else { return nil }
        let box = rectangle.intersection(imageFrame).intersection(viewport)
        guard !box.isNull, box.width > 1, box.height > 1 else { return nil }
        return CGRect(x: (box.minX - imageFrame.minX) / imageFrame.width,
                      y: (box.minY - imageFrame.minY) / imageFrame.height,
                      width: box.width / imageFrame.width, height: box.height / imageFrame.height)
    }
}

struct DepthSelectionOverlay: View {
    let imageFrame: CGRect
    @Binding var selection: CGRect?
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Color.clear
                if let selection {
                    Rectangle().fill(Palette.amber.opacity(0.12)).overlay(Rectangle().stroke(Palette.amber, lineWidth: 1.5))
                        .frame(width: selection.width * imageFrame.width, height: selection.height * imageFrame.height)
                        .offset(x: imageFrame.minX + selection.minX * imageFrame.width, y: imageFrame.minY + selection.minY * imageFrame.height)
                }
            }.contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 2).onChanged { value in
                    let a = value.startLocation, b = value.location
                    let rectangle = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
                    selection = PhotoSelectionGeometry.normalized(rectangle, imageFrame: imageFrame, viewport: CGRect(origin: .zero, size: geometry.size))
                }).clipped().accessibilityLabel("Draw a rectangular depth refinement region")
        }
    }
}

struct ComparisonDivider: View {
    @Binding var fraction: CGFloat
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Rectangle().fill(.white.opacity(0.9)).frame(width: 1, height: proxy.size.height)
                    .offset(x: proxy.size.width * fraction).allowsHitTesting(false)
                Image(systemName: "arrow.left.and.right").font(.caption.bold())
                    .frame(width: 44, height: 60)
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .contentShape(Rectangle())
                    .offset(x: min(max(0, proxy.size.width * fraction - 22), max(0, proxy.size.width - 44)), y: max(0, proxy.size.height / 2 - 30))
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("comparison")).onChanged { value in
                        fraction = min(1, max(0, value.location.x / max(1, proxy.size.width)))
                    })
                    .accessibilityLabel("Before and after divider")
                    .accessibilityValue("\(Int(fraction * 100)) percent original")
                    .accessibilityAdjustableAction { direction in
                        switch direction { case .increment: fraction = min(1, fraction + 0.1); case .decrement: fraction = max(0, fraction - 0.1); @unknown default: break }
                    }
                HStack {
                    Text("BEFORE").opacity(fraction > 0.12 ? 1 : 0)
                    Spacer()
                    Text("AFTER").opacity(fraction < 0.88 ? 1 : 0)
                }.font(.caption2.weight(.semibold)).tracking(1.5).padding(12)
                    .shadow(color: .black, radius: 3).allowsHitTesting(false)
            }.coordinateSpace(name: "comparison")
        }
    }
}

struct ComparisonPhoto: View {
    let before: UIImage
    let after: UIImage
    @State private var fraction: CGFloat = 0.5
    @State private var region = CGRect(x: 0, y: 0, width: 1, height: 1)
    var body: some View {
        ZStack {
            ZoomPhoto(image: after, visibleRegion: $region, before: before, comparisonFraction: fraction)
            ComparisonDivider(fraction: $fraction)
        }
    }
}
