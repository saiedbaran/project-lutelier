import SwiftUI

/// A direct-touch glass thumb, with a full-size gesture target and VoiceOver adjustment.
struct GlassStrengthSlider: View {
    @Binding var value: Double
    var onEditingChanged: (Bool) -> Void
    @State private var editing = false

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Strength").font(.caption)
                Spacer()
                Text(value, format: .percent.precision(.fractionLength(0))).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                let travel = max(1, geometry.size.width - 32)
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.06)).frame(height: 12)
                        .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 0.5))
                    Capsule().fill(Palette.amber.opacity(0.45)).frame(width: 16 + travel * min(1, max(0, value)), height: 12)
                    Capsule().fill(.clear).frame(width: 32, height: 24)
                        .glassEffect(.regular.interactive(), in: Capsule())
                        .scaleEffect(editing ? 1.12 : 1)
                        .offset(x: travel * min(1, max(0, value)))
                }.frame(height: 44).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                        if !editing { editing = true; onEditingChanged(true) }
                        value = min(1, max(0, (gesture.location.x - 16) / travel))
                    }.onEnded { _ in editing = false; onEditingChanged(false) })
            }.frame(height: 44)
        }.accessibilityElement(children: .ignore).accessibilityLabel("Strength")
            .accessibilityValue(value.formatted(.percent.precision(.fractionLength(0))))
            .accessibilityAdjustableAction { direction in
                onEditingChanged(true)
                switch direction { case .increment: value = min(1, value + 0.05); case .decrement: value = max(0, value - 0.05); @unknown default: break }
                onEditingChanged(false)
            }.onDisappear { if editing { editing = false; onEditingChanged(false) } }
    }
}
