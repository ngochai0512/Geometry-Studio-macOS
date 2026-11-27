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
    @State var dragObjectID: UUID?
    @State var dragObjectBasePositions: [UUID: Vec2] = [:]
    @State var dragObjectStartWorld: Vec2 = .zero
    @State var lastMoveSnap: Vec2?
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
    @State var lastRotationDetent: Int?
    @State var marqueeStart: CGPoint?
    @State var marqueeCurrent: CGPoint?
    @State var magnifyBase: Double?
    @State var lastClickAt: Date = .distantPast
    @State var dragPreviewStart: Vec2?
    @State var dragPreviewCurrent: Vec2?
    @State var metalReady = false
    @State var editingLabelID: UUID?
    @State var labelDraft = ""
    @FocusState var labelFieldFocused: Bool
    @State var editingCoordinateID: UUID?
    @State var coordinateDraftX = ""
    @State var coordinateDraftY = ""
    @FocusState var coordinateFieldFocused: Bool
    @State var hoveredObjectID: UUID?
    @State var dragNeedsHold = false
    @State var hudScreen: CGPoint?
    @State var selectionHandle: SelectionHandleKind?
    @State var handleBasePositions: [UUID: Vec2] = [:]
    @State var handleCenter: Vec2 = .zero
    @State var handleStartVector: Vec2 = .zero

    enum SelectionHandleKind: Hashable {
        case rotate
        case scale(corner: Int)
    }

    /// A press on an unselected object waits this long before it drags, so the
    /// click can select instead. Already-selected geometry drags immediately.
    let holdToDragDelay: TimeInterval = 0.16

    /// Printing always uses the paper palette, so a dark-canvas sketch does
    /// not print light ink on a white page.
    var palette: CanvasPalette {
        printing ? model.settings.paperPalette : model.settings.palette
    }
    var ink: Color {
        palette.ink.color
    }
    var secondaryInk: Color {
        palette.secondaryInk.color
    }
    var accent: Color {
        Color.accentColor
    }

    var usesMetal: Bool {
        !printing && model.settings.useMetalRenderer && MetalCanvas.isSupported
    }

    /// The Canvas closure draws outside the body's observation scope, so read
    /// the state it depends on here to keep redraws tied to model changes.
    /// Hover is only a drawing input while a draft is being placed; otherwise
    /// it belongs to the status bar and must not redraw the whole canvas.
    private var observedDrawingState: (
        SketchDocument,
        [UUID],
        [UUID],
        Vec2?,
        Set<UUID>,
        [UUID: [Vec2]],
        SketchTool,
        [SmartGuide],
        UUID?
    ) {
        let hover = model.draft.isEmpty ? nil : model.hoverWorld
        return (model.document, model.selection, model.draft, hover,
                model.tracedIDs, model.tracePaths, model.tool, model.smartGuides,
                hoveredObjectID)
    }

    var body: some View {
        let _ = observedDrawingState
        GeometryReader { geo in
            Group {
                if usesMetal {
                    ZStack {
                        Canvas { context, size in
                            drawBackground(context: &context, size: size)
                        }
                        .allowsHitTesting(false)

                        MetalCanvas(model: model) {
                            metalReady = true
                        }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .allowsHitTesting(false)

                        Canvas { context, size in
                            drawForeground(context: &context, size: size)
                        }
                        .allowsHitTesting(false)
                    }
                } else {
                    Canvas { context, size in
                        draw(context: &context, size: size)
                    }
                }
            }
            .background {
                if printing {
                    Color.white
                } else {
                    model.settings.backgroundColor.color
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(size: geo.size))
            .overlay(alignment: .topLeading) {
                canvasOverlay(size: geo.size)
            }
            .simultaneousGesture(magnification(size: geo.size))
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    if !model.isPointerOverCanvas {
                        model.isPointerOverCanvas = true
                    }
                    let world = model.worldPoint(point, size: geo.size)
                    if model.hoverWorld != world {
                        model.hoverWorld = world
                    }
                    model.lastPointerWorld = world
                    if dragStartScreen == nil {
                        let tolerance = 9 / model.settings.scale
                        let hit = model.hitTestLabel(world, tolerance: tolerance)
                            ?? model.hitTest(world, tolerance: tolerance)
                        if hoveredObjectID != hit {
                            hoveredObjectID = hit
                        }
                        updateCursor(for: hit)
                    }
                case .ended:
                    if model.isPointerOverCanvas {
                        model.isPointerOverCanvas = false
                    }
                    if model.hoverWorld != nil {
                        model.hoverWorld = nil
                    }
                    if hoveredObjectID != nil {
                        hoveredObjectID = nil
                    }
                    if !isPanning {
                        NSCursor.arrow.set()
                    }
                }
            }
            .onChange(of: model.tool) { _, _ in
                if !isPanning {
                    updateCursor(for: hoveredObjectID)
                }
            }
            .onChange(of: model.spacePanning) { _, _ in
                if !isPanning {
                    updateCursor(for: hoveredObjectID)
                }
            }
            .onChange(of: model.settings.useMetalRenderer) { _, _ in
                metalReady = false
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
            .accessibilityChildren {
                ForEach(model.objects.filter(\.visible)) { object in
                    Text(model.displayName(for: object))
                        .accessibilityLabel(model.displayName(for: object))
                        .accessibilityValue(accessibilityValue(for: object))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction {
                            model.select(object.id)
                        }
                }
            }
        }
    }

    /// The spoken value: measurement text when the object has one, otherwise
    /// its construction definition.
    private func accessibilityValue(for object: SketchObject) -> String {
        if case .caption(let text) = object.kind {
            return text
        }
        if let measurement = model.evaluated(object.id).text, !measurement.isEmpty {
            return measurement
        }
        return model.definition(for: object)
    }
}

#Preview("Canvas") {
    SketchCanvas(model: SketchModel.sample(), onTextAt: { _ in })
        .frame(width: 860, height: 620)
}
