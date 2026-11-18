import SwiftUI
import AppKit

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)

            Text("Geometry Studio")
                .font(.system(.title, design: .rounded, weight: .bold))
            Text("An app for exploring geometry through interactive shapes, drawings, and mathematical concepts.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Divider().padding(.horizontal, 30)

            VStack(alignment: .leading, spacing: 7) {
                Label("Native Swift and SwiftUI", systemImage: "swift")
                Label("Built for Apple silicon", systemImage: "cpu")
                Label("Drag a free point and every construction follows", systemImage: "hand.draw")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Text("The original is a 32-bit the legacy framework application whose geometry engine is written in C: its objects are plain C structs. This rebuild is a new Swift implementation, not a copy of its code.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 26)

            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(26)
        .frame(minWidth: 380)
    }
}

#Preview("About") {
    AboutView()
}
