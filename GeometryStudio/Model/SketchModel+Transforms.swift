import SwiftUI

extension SketchModel {

    // MARK: transform commands

    func reflectSelection() {
        guard let mirror = selectedStraights().last else {
            statusMessage = "Select a mirror line with the other objects"
            return
        }
        let sources = selection.filter { $0 != mirror }
        guard !sources.isEmpty else {
            statusMessage = "Select objects to reflect as well as the mirror"
            return
        }
        checkpoint("Reflect")
        var created: [UUID] = []
        for source in sources {
            let spec = TransformSpec(kind: .reflect, reference: mirror)
            created.append(commit(kind: .transformed(source: source, spec: spec), label: ""))
        }
        selection = created
        statusMessage = "Reflection created"
    }

    func rotateSelection(center: UUID, degrees: Double) {
        let sources = selection.filter { $0 != center }
        guard !sources.isEmpty else {
            statusMessage = "Select objects to rotate as well as the center"
            return
        }
        checkpoint("Rotate")
        var created: [UUID] = []
        for source in sources {
            let spec = TransformSpec(kind: .rotate, reference: center, angle: degrees)
            created.append(commit(kind: .transformed(source: source, spec: spec), label: ""))
        }
        selection = created
        statusMessage = "Rotation created"
    }

    func dilateSelection(center: UUID, factor: Double) {
        let sources = selection.filter { $0 != center }
        guard !sources.isEmpty else {
            statusMessage = "Select objects to dilate as well as the center"
            return
        }
        checkpoint("Dilate")
        var created: [UUID] = []
        for source in sources {
            let spec = TransformSpec(kind: .dilate, reference: center, factor: factor)
            created.append(commit(kind: .transformed(source: source, spec: spec), label: ""))
        }
        selection = created
        statusMessage = "Dilation created"
    }

    func translateSelection(dx: Double, dy: Double) {
        let sources = selection
        guard !sources.isEmpty else { statusMessage = "Select objects to translate"; return }
        checkpoint("Translate")
        var created: [UUID] = []
        for source in sources {
            let spec = TransformSpec(kind: .translate, dx: dx, dy: dy)
            created.append(commit(kind: .transformed(source: source, spec: spec), label: ""))
        }
        selection = created
        statusMessage = "Translation created"
    }

}
