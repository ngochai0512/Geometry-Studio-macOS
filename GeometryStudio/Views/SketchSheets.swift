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
    var shortcut: String = ""
    var action: () -> Void
}

/// A floating command palette: fuzzy search, arrow keys, a highlighted row and
/// a Recent section, rather than a modal list of every command.
struct CommandPalettePanel: View {
    var commands: [PaletteCommand]
    @Binding var recents: [String]
    var onClose: () -> Void

    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var visible: [PaletteRow] = []
    @State private var keyMonitor: Any?
    @FocusState private var searchFocused: Bool

    private struct PaletteRow: Identifiable {
        let id: String
        let command: PaletteCommand
        let section: String
    }

    private func refreshRows() {
        visible = computeRows()
        if selectedIndex >= visible.count {
            selectedIndex = max(0, visible.count - 1)
        }
    }

    private func computeRows() -> [PaletteRow] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            var result: [PaletteRow] = []
            for title in recents {
                if let command = commands.first(where: { $0.title == title }) {
                    result.append(PaletteRow(id: "recent-\(command.id)", command: command,
                                             section: "Recent"))
                }
            }
            let recentTitles = Set(result.map(\.command.title))
            for command in commands where !recentTitles.contains(command.title) {
                result.append(PaletteRow(id: "\(command.id)", command: command,
                                         section: "All Commands"))
            }
            return result
        }
        var scored: [(PaletteCommand, Int)] = []
        for command in commands {
            let score = fuzzyScore(command.title, needle: trimmed)
                ?? fuzzyScore(command.category, needle: trimmed).map { $0 - 6 }
            if let score {
                scored.append((command, score))
            }
        }
        return scored
            .sorted {
                $0.1 == $1.1 ? $0.0.title < $1.0.title : $0.1 > $1.1
            }
            .map {
                PaletteRow(id: "\($0.0.id)", command: $0.0,
                           section: "Results")
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search commands", text: $query)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .focused($searchFocused)
                Text("esc")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
            .padding(12)

            Divider()

            if visible.isEmpty {
                Text("No commands match.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(28)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(visible.enumerated()), id: \.element.id) { index, row in
                                if index == 0 || visible[index - 1].section != row.section {
                                    Text(row.section)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 10)
                                        .padding(.top, 8)
                                        .padding(.bottom, 2)
                                }
                                paletteRow(row, index: index)
                                    .id(row.id)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 360)
                    .onChange(of: selectedIndex) { _, index in
                        guard visible.indices.contains(index) else {
                            return
                        }
                        proxy.scrollTo(visible[index].id)
                    }
                }
            }

            Divider()

            HStack {
                Text("↑↓ to move   ↵ to run")
                Spacer()
                Text("\(visible.count) results")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(width: 560)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.quaternary, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 26, y: 12)
        .onAppear {
            refreshRows()
            searchFocused = true
            installKeyMonitor()
        }
        .onDisappear {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
            }
            keyMonitor = nil
        }
        .onChange(of: query) { _, _ in
            selectedIndex = 0
            refreshRows()
        }
    }

    private func paletteRow(_ row: PaletteRow, index: Int) -> some View {
        Button {
            run(row.command)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: row.command.symbol)
                    .foregroundStyle(.tint)
                    .frame(width: 18)
                Text(row.command.title)
                    .foregroundStyle(.primary)
                Spacer(minLength: 12)
                if !row.command.shortcut.isEmpty {
                    Text(row.command.shortcut)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Text(row.command.category)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(index == selectedIndex ? Color.accentColor.opacity(0.18)
                        : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                selectedIndex = index
            }
        }
        .padding(.horizontal, 6)
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else {
            return
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 53:
                onClose()
                return nil
            case 125:
                moveSelection(1)
                return nil
            case 126:
                moveSelection(-1)
                return nil
            case 36, 76:
                runSelected()
                return nil
            default:
                return event
            }
        }
    }

    private func moveSelection(_ delta: Int) {
        guard !visible.isEmpty else {
            return
        }
        selectedIndex = min(max(selectedIndex + delta, 0), visible.count - 1)
    }

    private func runSelected() {
        guard visible.indices.contains(selectedIndex) else {
            return
        }
        run(visible[selectedIndex].command)
    }

    private func run(_ command: PaletteCommand) {
        recents.removeAll { $0 == command.title }
        recents.insert(command.title, at: 0)
        if recents.count > 6 {
            recents.removeLast(recents.count - 6)
        }
        onClose()
        // Let the panel close before a command opens another sheet.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            command.action()
        }
    }

    /// Subsequence match with word-start and consecutive-run bonuses; nil when
    /// the needle does not appear in order.
    private func fuzzyScore(_ text: String, needle: String) -> Int? {
        guard !needle.isEmpty else {
            return 0
        }
        let haystack = text.lowercased()
        let query = needle.lowercased()
        var score = 0
        var cursor = haystack.startIndex
        var previous: String.Index?
        for character in query {
            guard let found = haystack[cursor...].firstIndex(of: character) else {
                return nil
            }
            score += 1
            if found == haystack.startIndex
                || haystack[haystack.index(before: found)] == " " {
                score += 5
            }
            if let previous, haystack.index(after: previous) == found {
                score += 3
            }
            previous = found
            cursor = haystack.index(after: found)
        }
        return score + max(0, 12 - haystack.count / 5)
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
    CommandPalettePanel(commands: [
        PaletteCommand(title: "Midpoint", category: "Construct", symbol: "circle.dotted") {},
        PaletteCommand(title: "Measure All", category: "Measure", symbol: "ruler") {},
        PaletteCommand(title: "Fit Sketch", category: "View",
                       symbol: "arrow.up.left.and.arrow.down.right",
                       shortcut: "⇧⌘F") {}
    ],
                       recents: .constant([]),
                       onClose: {})
}

#Preview("Undo History") {
    UndoHistorySheet(model: SketchModel.sample())
}
