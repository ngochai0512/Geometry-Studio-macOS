import Observation
import SwiftUI
import UniformTypeIdentifiers

/// The observable document SwiftUI opens, saves and autosaves. `SketchModel`
/// owns the live editing state; this type is the on-disk shape it syncs to.
@Observable
final class SketchFileDocument: Document {
    static let readableContentTypes: [UTType] = [.geometryStudioSketch, .json]
    static let writableContentTypes: [UTType] = [.geometryStudioSketch]

    var sketch: SketchDocument
    /// Not persisted. Set when a damaged file was partly recovered on load so
    /// the window can tell the user once.
    var recoveryNote: String?

    init(sketch: SketchDocument = SketchDocument(), recoveryNote: String? = nil) {
        self.sketch = sketch
        self.recoveryNote = recoveryNote
    }

    func reader(configuration: sending ReadConfiguration) -> sending FileWrapperDocumentReader<SketchSnapshot> {
        FileWrapperDocumentReader(configuration) { fileWrapper in
            guard let data = fileWrapper.regularFileContents else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return try SketchSnapshot.decode(from: data)
        }
    }

    func writer(configuration: sending WriteConfiguration) -> sending FileWrapperDocumentWriter<SketchSnapshot> {
        FileWrapperDocumentWriter(configuration) { snapshot, _ in
            FileWrapper(regularFileWithContents: try snapshot.encodedData())
        }
    }

    @MainActor
    func snapshot(contentType: UTType) async throws -> sending SketchSnapshot {
        SketchSnapshot(sketch: sketch, recoveryNote: recoveryNote)
    }

    @MainActor
    func apply(snapshot: sending SketchSnapshot, previous: sending SketchSnapshot?) async throws {
        sketch = snapshot.sketch
        recoveryNote = snapshot.recoveryNote
    }
}

/// The value the reader decodes and the writer encodes. Split from the
/// document so the codec is testable without a SwiftUI read configuration,
/// which has no public initializer.
struct SketchSnapshot {
    var sketch: SketchDocument
    var recoveryNote: String?

    static func decode(from data: Data) throws -> SketchSnapshot {
        do {
            let sketch = try JSONDecoder().decode(SketchDocument.self, from: data)
            return SketchSnapshot(sketch: sketch)
        } catch let error as DocumentError {
            throw error
        } catch {
            guard let result = SketchDocument.salvage(from: data) else {
                throw error
            }
            let note = "Geometry Studio recovered \(result.recovered) of \(result.total) objects "
                + "from a damaged file. Save a copy before making changes."
            return SketchSnapshot(sketch: result.document, recoveryNote: note)
        }
    }

    func encodedData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(sketch)
    }
}
