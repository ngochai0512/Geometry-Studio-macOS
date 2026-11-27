import AppKit
import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            AboutContent()

            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(26)
        .frame(minWidth: 380)
    }
}

/// The app's identity block, shared by the About sheet and the settings pane.
struct AboutContent: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text("Geometry Studio")
                    .font(.system(.title, design: .rounded, weight: .bold))
                Text(versionText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Text("An app for exploring geometry through interactive shapes, drawings, and mathematical concepts.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Divider().padding(.horizontal, 30)

            VStack(alignment: .leading, spacing: 7) {
                Label("Native Swift and SwiftUI", systemImage: "swift")
                Label("Built for Apple Silicon", systemImage: "cpu")
				Label("Fast and reliable", systemImage: "bolt")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

        }
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        switch (short, build) {
        case let (short?, build?):
            return "Version \(short) (\(build))"
        case let (short?, nil):
            return "Version \(short)"
        default:
            return "Development build"
        }
    }
}

#Preview("About") {
    AboutView()
}

#Preview("About content") {
    AboutContent()
        .padding(26)
        .frame(width: 420)
}
