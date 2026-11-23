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
