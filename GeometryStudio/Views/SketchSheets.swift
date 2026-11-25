import AppKit
import SwiftUI

// The modal cards ContentView presents. Each owns its chrome and validation;
// the values themselves stay in ContentView as bindings so reopening a sheet
// keeps the last entry, as it did when the forms were inline.

struct AddTextSheet: View {
    @Binding var text: String
    var onAdd: (String) -> Void

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Caption", text: $text, axis: .vertical)
                        .lineLimit(4...8)
                        .accessibilityLabel("Caption")
                } header: {
                    Label("Add Text", systemImage: "textformat")
                } footer: {
                    Text("Captions are objects on the canvas. They can be selected, moved and styled just like geometry.")
                }
            }
            .formStyle(.grouped)

            SheetFooter("Add", isEnabled: !trimmedText.isEmpty) { onAdd(trimmedText) }
        }
        .frame(minWidth: 420, minHeight: 240)
    }
}

struct FunctionSheet: View {
    @Binding var text: String
    var onPlot: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("f(x) =", text: $text)
                        .textFieldStyle(.bordered)
                        .textInputBorderShape(.roundedRectangle)
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Label("Plot a Function", systemImage: "function")
                } footer: {
                    Text("Type an expression in x. Examples: sin(x), x^2 - 2, 3cos(2x) + 1.")
                }
            }
            .formStyle(.grouped)

            SheetFooter("Plot", isEnabled: Expression(text) != nil) { onPlot(text) }
        }
        .frame(minWidth: 420, minHeight: 240)
    }
}

struct CalculationSheet: View {
    @Binding var text: String
    /// Measurement labels with spaces turned into underscores.
    var names: [String]
    var onAdd: (String) -> Void

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("expression", text: $text)
                        .textFieldStyle(.bordered)
                        .textInputBorderShape(.roundedRectangle)
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Label("Calculate", systemImage: "function")
                } footer: {
                    Text("Use measurement names (spaces become underscores), numbers, + − × ÷, ^ and functions such as sqrt, sin and cos.")
                }

                if !names.isEmpty {
                    Section("Measurements") {
                        FlowChips(items: names) { name in
                            if !text.isEmpty && !text.hasSuffix(" ") && !text.hasSuffix("(") {
                                text += " "
                            }
                            text += name
                        }
                    }
                }
            }
            .formStyle(.grouped)

            SheetFooter("Add", isEnabled: !trimmedText.isEmpty) { onAdd(text) }
        }
        .frame(minWidth: 420, minHeight: 240)
    }
}

struct CircleRadiusSheet: View {
    @Binding var radius: Double
    var centerName: String?
    var unit: String
    var onConstruct: (Double) -> Void

    private var isValid: Bool {
        centerName != nil && radius.isFinite && radius > 0
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    if let centerName {
                        LabeledContent("Center") {
                            Text(centerName)
                                .foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Radius") {
                        HStack(spacing: 6) {
                            TextField("Radius", value: $radius, format: .number)
                                .labelsHidden()
                                .multilineTextAlignment(.trailing)
                                .frame(minWidth: 80)
                            Text(unit)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Label("Circle by Radius", systemImage: "circle")
                } footer: {
                    if centerName == nil {
                        Text("Select a center point first.")
                            .foregroundStyle(.orange)
                    } else {
                        Text("Draw a circle with a fixed radius around the selected point.")
                    }
                }
            }
            .formStyle(.grouped)

            SheetFooter("Create", isEnabled: isValid) { onConstruct(radius) }
        }
        .frame(minWidth: 420, minHeight: 240)
    }
}

// MARK: - Onboarding, palette and history

private let welcomeTips: [(String, String)] = [
    ("hand.draw", "Drag a free point and every construction follows"),
    ("cursorarrow.click.2", "Shift-click adds to the selection; drag on empty space to marquee"),
    ("character.cursor.ibeam", "Double-click a label to rename it, or drag the label grip"),
    ("command", "⌘K opens the command palette; ⌘D duplicates the selection"),
    ("ruler", "Select regions and paths to see area and perimeter in the status bar")
]

struct WelcomeSheet: View {
    var isFirstRun: Bool
    var onTemplate: (SketchTemplate) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "compass.drawing")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text(isFirstRun ? "Welcome to Geometry Studio" : "Tips and Shortcuts")
                .font(.system(.title2, design: .rounded, weight: .semibold))
            Text("Construct points, lines, circles and polygons, then drag a free point to see the whole construction update.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 430)

            VStack(alignment: .leading, spacing: 9) {
                ForEach(welcomeTips.indices, id: \.self) { index in
                    Label {
                        Text(welcomeTips[index].1)
                    } icon: {
                        Image(systemName: welcomeTips[index].0)
                            .foregroundStyle(.tint)
                    }
                    .font(.subheadline)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )

            HStack(spacing: 10) {
                Spacer()
                Button("Start with a Triangle") {
                    onTemplate(.triangle)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                Button("Done") {
                    dismiss()
                }
            }
        }
        .padding(24)
        .frame(minWidth: 520)
    }
}

/// One command palette entry.
struct PaletteCommand: Identifiable {
    let id = UUID()
    var title: String
    var category: String
    var symbol: String
    var action: () -> Void
}

struct CommandPaletteSheet: View {
    var commands: [PaletteCommand]

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var filtered: [PaletteCommand] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return commands
        }
        return commands.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
                || $0.category.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search constructions, measurements and commands", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit {
                        runFirst()
                    }
            }
            .padding(14)

            Divider()

            if filtered.isEmpty {
                Text("No commands match.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered) { command in
                    Button {
                        run(command)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: command.symbol)
                                .foregroundStyle(.tint)
                                .frame(width: 18)
                            Text(command.title)
                            Spacer()
                            Text(command.category)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 520, minHeight: 420)
        .onAppear {
            searchFocused = true
        }
        .onExitCommand {
            dismiss()
        }
    }

    private func runFirst() {
        guard let first = filtered.first else {
            return
        }
        run(first)
    }

    private func run(_ command: PaletteCommand) {
        dismiss()
        // Let the sheet finish dismissing before a command opens another one.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            command.action()
        }
    }
}

struct UndoHistorySheet: View {
    let model: SketchModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Undo History")
                    .font(.title3.weight(.semibold))
                Text("Choose a step to return to. Steps after it can be redone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)

            Divider()

            List {
                historyRow(index: 0, title: "Initial State")
                ForEach(Array(model.undoHistory.enumerated()), id: \.element.id) { index, entry in
                    historyRow(index: index + 1, title: entry.name)
                }
            }
            .listStyle(.inset)

            SheetFooter("Done") {}
        }
        .frame(minWidth: 440, minHeight: 420)
    }

    private func historyRow(index: Int, title: String) -> some View {
        let current = index == model.undoHistoryIndex
        return Button {
            model.travelHistory(to: index)
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Text("\(index)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 22, alignment: .trailing)
                Text(title)
                    .foregroundStyle(current ? Color.primary : Color.secondary)
                Spacer()
                if current {
                    Image(systemName: "smallcircle.filled.circle")
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Current state")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(index > model.undoHistoryIndex && !model.canRedo)
    }
}

struct ProtocolSheet: View {
    var steps: [String]

    var body: some View {
        VStack(spacing: 0) {
            if steps.isEmpty {
                Text("No construction steps yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(index + 1).")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .trailing)
                        Text(step)
                            .textSelection(.enabled)
                    }
                }
            }
            SheetFooter("Done") {}
        }
        .frame(minWidth: 560, minHeight: 420)
    }
}

/// The Cancel/confirm pair every sheet closes with.
private struct SheetFooter: View {
    var title: String
    var isEnabled: Bool
    var action: () -> Void

    @Environment(\.dismiss) private var dismiss

    init(_ title: String, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(title) {
                    action()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isEnabled)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }
}

#Preview("Add Text") {
    AddTextSheet(text: .constant("Let ABC be a triangle.")) { _ in }
}

#Preview("Plot Function") {
    FunctionSheet(text: .constant("sin(x)")) { _ in }
}

#Preview("Calculate") {
    CalculationSheet(text: .constant("d1 + d2"),
                    names: ["d1", "d2", "angle_A"]) { _ in }
}

#Preview("Circle by Radius") {
    CircleRadiusSheet(radius: .constant(2), centerName: "A", unit: "in") { _ in }
}

#Preview("Construction Protocol") {
    ProtocolSheet(steps: [
        "Free point A at (0.00, 0.00) in",
        "Free point B at (2.00, 1.00) in",
        "Segment AB",
        "Midpoint M of A and B"
    ])
}

#Preview("Welcome") {
    WelcomeSheet(isFirstRun: true,
                 onTemplate: { _ in })
}

#Preview("Command Palette") {
    CommandPaletteSheet(commands: [
        PaletteCommand(title: "Midpoint", category: "Construct", symbol: "circle.dotted") {},
        PaletteCommand(title: "Measure All", category: "Measure", symbol: "ruler") {},
        PaletteCommand(title: "Fit Sketch", category: "View",
                       symbol: "arrow.up.left.and.arrow.down.right") {}
    ])
}

#Preview("Undo History") {
    UndoHistorySheet(model: SketchModel.sample())
}
