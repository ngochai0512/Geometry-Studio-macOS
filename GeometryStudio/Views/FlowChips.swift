import SwiftUI

struct FlowChips: View {
    var items: [String]
    var action: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 5)], alignment: .leading, spacing: 5) {
            ForEach(items, id: \.self) { item in
                Button(item) { action(item) }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .lineLimit(1)
            }
        }
    }
}

#Preview("Flow chips") {
    FlowChips(items: ["Distance", "Length", "Radius"]) { _ in }
        .padding()
        .frame(width: 260)
}
