import SwiftUI
import AppKit

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.18, green: 0.51, blue: 0.96),
                                                  Color(red: 0.44, green: 0.31, blue: 0.90)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "compass.drawing")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 84, height: 84)
            .shadow(color: .black.opacity(0.18), radius: 12, y: 5)

            Text("Geometry Studio")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text("A dynamic geometry sketchpad for macOS")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)

            Divider().padding(.horizontal, 30)

            VStack(alignment: .leading, spacing: 7) {
                Label("Native Swift and SwiftUI", systemImage: "swift")
                Label("Built for Apple silicon", systemImage: "cpu")
                Label("Drag a free point and every construction follows", systemImage: "hand.draw")
            }
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)

            Text("The original is a 32-bit the legacy framework application whose geometry engine is written in C: its objects are plain C structs. This rebuild is a new Swift implementation, not a copy of its code.")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 26)

            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(26)
        .frame(width: 380)
    }
}
