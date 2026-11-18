import SwiftUI

// The modal cards ContentView presents. Each owns its chrome and validation;
// the values themselves stay in ContentView as bindings so reopening a sheet
// keeps the last entry, as it did when the forms were inline.

struct AddTextSheet: View {
    @Binding var text: String
    var onAdd: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Add Text", systemImage: "textformat")
                .font(.headline)
            Text("Captions are objects on the canvas. They can be selected, moved and styled just like geometry.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $text)
                .font(.system(size: 13))
                .frame(height: 88)
                .padding(6)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.1))
                }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        onAdd(trimmed)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 420)
    }
}

struct RotateSheet: View {
    @Binding var angle: Double
    /// Nil when no point is available as a centre; the buttons disable.
    var centerName: String?
    var onRotate: (Double) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Rotate", systemImage: "rotate.right")
                .font(.headline)
            Text("Rotate the selected objects around a point.")
                .font(.subheadline).foregroundStyle(.secondary)
            if let centerName {
                LabeledContent("Center") {
                    Text(centerName).foregroundStyle(.secondary)
                }
            } else {
                Text("Select a center point as well as the objects to rotate.")
                    .font(.caption).foregroundStyle(.orange)
            }
            LabeledContent("Angle") {
                HStack(spacing: 6) {
                    TextField("Angle", value: $angle, format: .number)
                        .labelsHidden()
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                    Text("degrees").foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Rotate") {
                    onRotate(angle)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(centerName == nil)
            }
        }
        .padding(22)
        .frame(width: 400)
    }
}

struct DilateSheet: View {
    @Binding var factor: Double
    var centerName: String?
    var onDilate: (Double) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Dilate", systemImage: "arrow.up.left.and.arrow.down.right")
                .font(.headline)
            Text("Scale the selected objects about a center point.")
                .font(.subheadline).foregroundStyle(.secondary)
            if let centerName {
                LabeledContent("Center") {
                    Text(centerName).foregroundStyle(.secondary)
                }
            } else {
                Text("Select a center point as well as the objects to dilate.")
                    .font(.caption).foregroundStyle(.orange)
            }
            LabeledContent("Scale factor") {
                TextField("Factor", value: $factor, format: .number)
                    .labelsHidden()
                    .frame(width: 80)
                    .multilineTextAlignment(.trailing)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Dilate") {
                    onDilate(factor)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(centerName == nil)
            }
        }
        .padding(22)
        .frame(width: 400)
    }
}

struct TranslateSheet: View {
    @Binding var dx: Double
    @Binding var dy: Double
    var unit: String
    var onTranslate: (Double, Double) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Translate", systemImage: "arrow.right")
                .font(.headline)
            Text("Move a copy of the selected objects by a fixed amount.")
                .font(.subheadline).foregroundStyle(.secondary)
            LabeledContent("Horizontal") {
                HStack(spacing: 6) {
                    TextField("dx", value: $dx, format: .number)
                        .labelsHidden()
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                    Text(unit).foregroundStyle(.secondary)
                }
            }
            LabeledContent("Vertical") {
                HStack(spacing: 6) {
                    TextField("dy", value: $dy, format: .number)
                        .labelsHidden()
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                    Text(unit).foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Translate") {
                    onTranslate(dx, dy)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 400)
    }
}

struct FunctionSheet: View {
    @Binding var text: String
    var onPlot: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Plot a Function", systemImage: "function")
                .font(.headline)
            Text("Type an expression in x. Examples: sin(x), x^2 - 2, 3cos(2x) + 1.")
                .font(.subheadline).foregroundStyle(.secondary)
            TextField("f(x) =", text: $text)
                .textFieldStyle(.bordered)
                .textInputBorderShape(.roundedRectangle)
                .font(.system(size: 14, design: .monospaced))
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Plot") {
                    onPlot(text)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(Expression(text) == nil)
            }
        }
        .padding(22)
        .frame(width: 460)
    }
}

struct CalculationSheet: View {
    @Binding var text: String
    /// Measurement labels with spaces turned into underscores.
    var names: [String]
    var onAdd: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Calculate", systemImage: "function")
                .font(.headline)
            Text("Use measurement names (spaces become underscores), numbers, + − × ÷, ^ and functions such as sqrt, sin and cos.")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("expression", text: $text)
                .textFieldStyle(.bordered)
                .textInputBorderShape(.roundedRectangle)
                .font(.system(size: 14, design: .monospaced))
            if !names.isEmpty {
                Text("Measurements").font(.caption).foregroundStyle(.secondary)
                FlowChips(items: names) { name in
                    if !text.isEmpty && !text.hasSuffix(" ") && !text.hasSuffix("(") {
                        text += " "
                    }
                    text += name
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    onAdd(text)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 480)
    }
}
