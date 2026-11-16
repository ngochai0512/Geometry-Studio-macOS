import SwiftUI
import UniformTypeIdentifiers

/// The value SwiftUI's document architecture reads and writes. `SketchModel`
/// owns the live editing state; this type is the on-disk shape it syncs to.
struct SketchFileDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.geometryStudioSketch, .json]
    }

    static var writableContentTypes: [UTType] {
        [.geometryStudioSketch]
    }

    var sketch: SketchDocument
    /// Not persisted. Set when a damaged file was partly recovered on load so
    /// the window can tell the user once.
    var recoveryNote: String?

    init(sketch: SketchDocument = SketchDocument(), recoveryNote: String? = nil) {
        self.sketch = sketch
        self.recoveryNote = recoveryNote
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self = try SketchFileDocument.decode(from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try encodedData())
    }

    /// Split from `init(configuration:)` so the codec is testable without a
    /// SwiftUI read configuration, which has no public initializer.
    static func decode(from data: Data) throws -> SketchFileDocument {
        do {
            let sketch = try JSONDecoder().decode(SketchDocument.self, from: data)
            return SketchFileDocument(sketch: sketch)
        } catch let error as DocumentError {
            throw error
        } catch {
            guard let result = SketchDocument.salvage(from: data) else {
                throw error
            }
            let note = "Geometry Studio recovered \(result.recovered) of \(result.total) objects "
                + "from a damaged file. Save a copy before making changes."
            return SketchFileDocument(sketch: result.document, recoveryNote: note)
        }
    }

    func encodedData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(sketch)
    }
}
