import SwiftUI

/// The bottom strip. The tool hint is persistent on the left, live pointer and
/// selection numbers sit in the middle, and save/status messages fade on the
/// right instead of lingering forever.
struct SketchStatusBar: View {
    let model: SketchModel

    @State private var fadingStatus = ""

    var body: some View {
        HStack(spacing: 10) {
            Label(model.tool.title, systemImage: model.tool.symbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(model.tool.hint)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            if !model.draft.isEmpty {
                Divider().frame(height: 14)
                Text("\(model.draft.count) picked")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                if model.tool == .polygon && model.draft.count >= 3 {
                    Button("Close Polygon") { model.finishPolygon() }
                        .buttonStyle(.borderless)
                        .font(.caption.weight(.semibold))
                }
                Button("Cancel") { model.cancelDraft() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }

            Spacer(minLength: 6)

            if let hover = model.hoverWorld {
                Text("x \(fmt(hover.x / model.settings.lengthUnit.perUnit))   y \(fmt(hover.y / model.settings.lengthUnit.perUnit)) \(model.settings.lengthUnit.short)")
                    .font(.system(.caption, design: .monospaced, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if !model.selection.isEmpty {
                Text("\(model.selection.count) selected")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                if let metrics = model.selectionMetrics() {
                    Text(selectionMetricsText(metrics))
                        .font(.system(.caption, design: .monospaced, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Text("\(model.objects.filter(\.visible).count) objects")
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(.tertiary)

            if !fadingStatus.isEmpty {
                Divider().frame(height: 14)
                Text(fadingStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .frame(minHeight: 26)
        .background(.bar)
        .overlay(alignment: .top) { Divider().opacity(0.5) }
        .animation(.easeInOut(duration: 0.25), value: fadingStatus)
        .task(id: model.statusMessage) {
            let message = model.statusMessage
            fadingStatus = message
            guard !message.isEmpty else {
                return
            }
            try? await Task.sleep(for: .seconds(3))
            if model.statusMessage == message {
                fadingStatus = ""
            }
        }
    }

    private func fmt(_ v: Double) -> String {
        let digits = max(0, min(model.settings.precision, 6))
        return String(format: "%.\(digits)f", v)
    }

    private func selectionMetricsText(_ metrics: SketchModel.SelectionMetrics) -> String {
        let formatter = model.evaluator()
        var parts: [String] = []
        if metrics.area > 0 {
            parts.append("A \(formatter.formatArea(metrics.area))")
        }
        if metrics.perimeter > 0 {
            parts.append("P \(formatter.formatLength(metrics.perimeter))")
        }
        return parts.joined(separator: " · ")
    }
}

#Preview("Status bar") {
    SketchStatusBar(model: SketchModel.sample())
        .frame(width: 900)
}
