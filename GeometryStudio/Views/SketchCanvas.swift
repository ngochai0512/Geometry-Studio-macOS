import SwiftUI
import AppKit

struct SketchCanvas: View {
    let model: SketchModel
    var onTextAt: (Vec2) -> Void
    /// Printing renders a clean white page instead of the screen tint.
    var printing: Bool = false

    @State var dragStartScreen: CGPoint?
    @State var panStartCenter: Vec2 = .zero
    @State var isPanning = false
    @State var dragPointID: UUID?
    @State var dragLabelID: UUID?
    @State var dragLabelBaseOffset: Vec2 = .zero
    @State var dragLabelBasePosition: Vec2 = .zero
    @State var dragLabelIsCaption = false
    @State var dragCheckpointed = false
    @State var didMove = false
    @State var pressHitID: UUID?
    @State var pressStartedAt: Date = .distantPast
    @State var holdReached = false
    @State var holdSelectionDone = false
    @State var lastSnapWorld: Vec2?
    @State var marqueeStart: CGPoint?
    @State var marqueeCurrent: CGPoint?
    @State var magnifyBase: Double?
    @State var lastClickAt: Date = .distantPast

    /// A click selects; the pointer must rest this long before a drag moves
    /// anything. The delay keeps click-selection from turning into an
    /// accidental micro-drag.
    let holdToDragDelay: TimeInterval = 0.16

    var ink: Color {
        RGBA.ink.color
    }
    var secondaryInk: Color {
        RGBA.secondaryInk.color
    }
    var accent: Color {
        Color.accentColor
    }

    /// The Canvas closure draws outside the body's observation scope, so read
    /// the state it depends on here to keep redraws tied to model changes.
    private var observedDrawingState: (
        SketchDocument,
        [UUID],
        [UUID],
        Vec2?,
        Set<UUID>,
        [UUID: [Vec2]],
        SketchTool
    ) {
        (model.document, model.selection, model.draft, model.hoverWorld,
         model.tracedIDs, model.tracePaths, model.tool)
    }

    var body: some View {
        let _ = observedDrawingState
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
                    if model.tool == .pan, !isPanning {
                        NSCursor.openHand.set()
                    }
                case .ended:
                    model.isPointerOverCanvas = false
                    model.hoverWorld = nil
                    if !isPanning {
                        NSCursor.arrow.set()
                    }
                }
            }
            .onChange(of: model.tool) { _, tool in
                if tool == .pan {
                    if model.isPointerOverCanvas, !isPanning {
                        NSCursor.openHand.set()
                    }
                } else if !isPanning {
                    NSCursor.arrow.set()
                }
            }
            .onDisappear {
                NSCursor.arrow.set()
            }
            .onAppear {
                model.canvasSize = geo.size
                if model.objects.isEmpty && model.settings.scale == SketchMetrics.pixelsPerCentimetre {
                    model.setZoom(SketchMetrics.pixelsPerCentimetre)
                }
            }
            .onChange(of: geo.size) { _, newSize in
                if model.canvasSize != newSize {
                    model.canvasSize = newSize
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
