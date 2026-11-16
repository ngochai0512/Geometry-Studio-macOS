import SwiftUI

extension SketchModel {

    // MARK: measurement commands

    func measure(_ kind: MeasureKind) {
        let ids = selection
        var e = evaluator()
        var refs: [UUID] = []
        switch kind {
        case .distance:
            let pts = ids.filter { e.evaluate($0).point != nil }
            guard pts.count >= 2 else { statusMessage = "Select two points"; return }
            refs = Array(pts.prefix(2))
        case .length, .perimeter, .circumference, .radius, .slope:
            guard let id = ids.first(where: { e.evaluate($0).path != nil }) else {
                statusMessage = "Select a path first"; return
            }
            refs = [id]
        case .angle:
            let pts = ids.filter { e.evaluate($0).point != nil }
            guard pts.count >= 3 else { statusMessage = "Select three points"; return }
            refs = Array(pts.prefix(3))
        case .area:
            guard let id = ids.first(where: { e.evaluate($0).path != nil }) else {
                statusMessage = "Select a polygon or circle"; return
            }
            refs = [id]
        case .ratio:
            let paths = ids.filter { e.evaluate($0).path?.straight != nil }
            guard paths.count >= 2 else { statusMessage = "Select two segments"; return }
            refs = Array(paths.prefix(2))
        case .coordinates:
            guard let id = ids.first(where: { e.evaluate($0).point != nil }) else {
                statusMessage = "Select a point"; return
            }
            refs = [id]
        case .equation:
            guard let id = ids.first(where: { e.evaluate($0).path != nil }) else {
                statusMessage = "Select a line or circle"; return
            }
            refs = [id]
        }
        _ = e
        checkpoint()
        let id = commit(kind: .measurement(kind, refs: refs), label: "")
        selection = [id]
        statusMessage = "\(kind.title) measured"
    }

    func addCalculation(expression: String) {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        checkpoint()
        let id = commit(kind: .calculation(trimmed), label: "")
        selection = [id]
        isDirty = true
        statusMessage = "Calculation added"
    }

}
