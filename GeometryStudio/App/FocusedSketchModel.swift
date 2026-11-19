import SwiftUI

/// Publishes the active window's model to the menu commands.
struct SketchModelFocusedValueKey: FocusedValueKey {
    typealias Value = SketchModel
}

extension FocusedValues {
    var sketchModel: SketchModel? {
        get {
            self[SketchModelFocusedValueKey.self]
        }
        set {
            self[SketchModelFocusedValueKey.self] = newValue
        }
    }
}
