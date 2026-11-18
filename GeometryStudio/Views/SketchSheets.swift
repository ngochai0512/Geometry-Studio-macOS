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

struct RotateSheet: View {
    @Binding var angle: Double
    /// Nil when no point is available as a centre; the buttons disable.
    var centerName: String?
    var onRotate: (Double) -> Void

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
                    LabeledContent("Angle") {
                        HStack(spacing: 6) {
                            TextField("Angle", value: $angle, format: .number)
                                .labelsHidden()
                                .multilineTextAlignment(.trailing)
                                .frame(minWidth: 80)
                            Text("degrees")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Label("Rotate", systemImage: "rotate.right")
                } footer: {
                    if centerName == nil {
                        Text("Select a center point as well as the objects to rotate.")
                            .foregroundStyle(.orange)
                    } else {
                        Text("Rotate the selected objects around a point.")
                    }
                }
            }
            .formStyle(.grouped)

            SheetFooter("Rotate", isEnabled: centerName != nil) { onRotate(angle) }
        }
        .frame(minWidth: 420, minHeight: 240)
    }
}

struct DilateSheet: View {
    @Binding var factor: Double
    var centerName: String?
    var onDilate: (Double) -> Void

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
                    LabeledContent("Scale factor") {
                        TextField("Factor", value: $factor, format: .number)
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(minWidth: 80)
                    }
                } header: {
                    Label("Dilate", systemImage: "arrow.up.left.and.arrow.down.right")
                } footer: {
                    if centerName == nil {
                        Text("Select a center point as well as the objects to dilate.")
                            .foregroundStyle(.orange)
                    } else {
                        Text("Scale the selected objects about a center point.")
                    }
                }
            }
            .formStyle(.grouped)

            SheetFooter("Dilate", isEnabled: centerName != nil) { onDilate(factor) }
        }
        .frame(minWidth: 420, minHeight: 240)
    }
}

struct TranslateSheet: View {
    @Binding var dx: Double
    @Binding var dy: Double
    var unit: String
    var onTranslate: (Double, Double) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    LabeledContent("Horizontal") {
                        HStack(spacing: 6) {
                            TextField("dx", value: $dx, format: .number)
                                .labelsHidden()
                                .multilineTextAlignment(.trailing)
                                .frame(minWidth: 80)
                            Text(unit)
                                .foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Vertical") {
                        HStack(spacing: 6) {
                            TextField("dy", value: $dy, format: .number)
                                .labelsHidden()
                                .multilineTextAlignment(.trailing)
                                .frame(minWidth: 80)
                            Text(unit)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Label("Translate", systemImage: "arrow.right")
                } footer: {
                    Text("Move a copy of the selected objects by a fixed amount.")
                }
            }
            .formStyle(.grouped)

            SheetFooter("Translate") { onTranslate(dx, dy) }
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

#Preview("Rotate") {
    RotateSheet(angle: .constant(90), centerName: "A") { _ in }
}

#Preview("Dilate") {
    DilateSheet(factor: .constant(2), centerName: "A") { _ in }
}

#Preview("Translate") {
    TranslateSheet(dx: .constant(1), dy: .constant(0), unit: "in") { _, _ in }
}

#Preview("Plot Function") {
    FunctionSheet(text: .constant("sin(x)")) { _ in }
}

#Preview("Calculate") {
    CalculationSheet(text: .constant("d1 + d2"),
                    names: ["d1", "d2", "angle_A"]) { _ in }
}
