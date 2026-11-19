import SwiftUI
import AppKit

struct SketchCanvas: View {
    @ObservedObject var model: SketchModel
    var onTextAt: (Vec2) -> Void
    /// Printing renders a clean white page instead of the screen tint.
    var printing: Bool = false

    @State var dragStartScreen: CGPoint?
    @State var dragPointID: UUID?
    @State var dragLabelID: UUID?
    @State var dragLabelBaseOffset: Vec2 = .zero
    @State var dragLabelBasePosition: Vec2 = .zero
    @State var dragLabelIsCaption = false
    @State var dragCheckpointed = false
    @State var didMove = false
    @State var marqueeStart: CGPoint?
    @State var marqueeCurrent: CGPoint?
    @State var magnifyBase: Double?
    @State var lastClickAt: Date = .distantPast

    var ink: Color {
        RGBA.ink.color
    }
    var secondaryInk: Color {
        RGBA.secondaryInk.color
    }
    var accent: Color {
        Color.accentColor
    }

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                draw(context: &context, size: size)
            }
            .background {
                if printing {
                    Color.white
                } else {
                    // Ink colours are fixed, so the paper stays light in every appearance.
                    Color(nsColor: .textBackgroundColor)
                        .environment(\.colorScheme, .light)
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(size: geo.size))
            .simultaneousGesture(magnification(size: geo.size))
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    model.isPointerOverCanvas = true
                    model.hoverWorld = model.worldPoint(point, size: geo.size)
                case .ended:
                    model.isPointerOverCanvas = false
                    model.hoverWorld = nil
                }
            }
            .onAppear {
                if model.objects.isEmpty && model.settings.scale == SketchMetrics.pixelsPerCentimetre {
                    model.setZoom(SketchMetrics.pixelsPerCentimetre)
                }
            }
            .accessibilityLabel("Geometry canvas")
        }
    }
}

#Preview("Canvas") {
    SketchCanvas(model: SketchModel.sample(), onTextAt: { _ in })
        .frame(width: 860, height: 620)
}
