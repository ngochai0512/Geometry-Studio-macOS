import SwiftUI
import AppKit

struct SketchCanvas: View {
    @ObservedObject var model: SketchModel
    var onTextAt: (Vec2) -> Void

    @State var canvasSize: CGSize = .zero
    @State var dragStartWorld: Vec2?
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

    var ink: Color { RGBA.ink.color }
    var secondaryInk: Color { RGBA.secondaryInk.color }
    var accent: Color { Color.accentColor }

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                draw(context: &context, size: size)
            }
            .background(
                LinearGradient(colors: [Color(red: 0.995, green: 0.995, blue: 0.998),
                                        Color(red: 0.975, green: 0.977, blue: 0.985)],
                               startPoint: .top, endPoint: .bottom)
            )
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
                canvasSize = geo.size
                if model.objects.isEmpty && model.settings.scale == SketchMetrics.pixelsPerCentimetre {
                    model.setZoom(SketchMetrics.pixelsPerCentimetre)
                }
            }
            .onChange(of: geo.size) { newValue in
                canvasSize = newValue
            }
            .accessibilityLabel("Geometry canvas")
        }
    }
}
