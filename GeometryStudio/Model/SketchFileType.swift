import UniformTypeIdentifiers

extension UTType {
    /// Matches the exported declaration in `App/Info.plist`. Declaring it in
    /// code keeps the open and save panels filtering by `.gsp` even when the
    /// executable runs unbundled under `swift run`.
    static let geometryStudioSketch = UTType(exportedAs: "com.geometrystudio.gsp",
                                             conformingTo: .json)
}
