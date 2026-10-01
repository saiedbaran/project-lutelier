import SwiftUI
import UIKit

struct ZoomPhoto: UIViewRepresentable {
    let image: UIImage
    @Binding var visibleRegion: CGRect
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
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
        context.coordinator.imageView.image = image
        DispatchQueue.main.async {
            guard scroll.bounds.width > 0, scroll.bounds.height > 0 else { return }
            let scale = min(scroll.bounds.width / image.size.width, scroll.bounds.height / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            if context.coordinator.imageView.bounds.size != size {
                scroll.setZoomScale(1, animated: false)
                context.coordinator.imageView.frame = CGRect(origin: .zero, size: size)
                scroll.contentSize = size
                context.coordinator.center(scroll)
            }
        }
    }
    class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ZoomPhoto
        let imageView = UIImageView()
        init(_ parent: ZoomPhoto) { self.parent = parent }
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
        func scrollViewDidZoom(_ scroll: UIScrollView) { center(scroll); updateRegion(scroll) }
        func scrollViewDidScroll(_ scroll: UIScrollView) { updateRegion(scroll) }
        func center(_ scroll: UIScrollView) {
            let x = max((scroll.bounds.width - scroll.contentSize.width) / 2, 0)
            let y = max((scroll.bounds.height - scroll.contentSize.height) / 2, 0)
            scroll.contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
        }
        func updateRegion(_ scroll: UIScrollView) {
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
