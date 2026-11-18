import SwiftUI

/// The bottom strip: pointer position or tool hint on the left, draft actions
/// in the middle, status and counts on the right.
struct SketchStatusBar: View {
    @ObservedObject var model: SketchModel

    var body: some View {
        HStack(spacing: 10) {
            if let hover = model.hoverWorld {
                Text("x \(fmt(hover.x / model.settings.lengthUnit.perUnit))   y \(fmt(hover.y / model.settings.lengthUnit.perUnit)) \(model.settings.lengthUnit.short)")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                Text(model.tool.hint)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !model.draft.isEmpty {
                Divider().frame(height: 14)
                Text("\(model.draft.count) picked")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                if model.tool == .polygon && model.draft.count >= 3 {
                    Button("Close Polygon") { model.finishPolygon() }
                        .buttonStyle(.borderless)
                        .font(.system(size: 10.5, weight: .semibold))
                }
                Button("Cancel") { model.cancelDraft() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10.5))
            }

            Spacer(minLength: 6)

            if !model.statusMessage.isEmpty {
                Text(model.statusMessage)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Divider().frame(height: 14)

            Text("\(model.objects.filter(\.visible).count) objects")
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            if !model.selection.isEmpty {
                Text("\(model.selection.count) selected")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 26)
        .background(.bar)
        .overlay(alignment: .top) { Divider().opacity(0.5) }
    }

    private func fmt(_ v: Double) -> String {
        String(format: "%.2f", v)
    }
}

#Preview("Status bar") {
    SketchStatusBar(model: SketchModel.sample())
        .frame(width: 900)
}
