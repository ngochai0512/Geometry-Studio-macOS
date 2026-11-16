import Foundation

struct SketchAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// Something the app can put back after a failure: an autosaved draft from an
/// earlier session, or the readable part of a damaged sketch.
enum RecoveryOffer: Identifiable {
    case draft(DraftRecord, URL)
    case salvage(SalvageResult)

    var id: String {
        switch self {
        case .draft(_, let url):
            return url.path
        case .salvage(let result):
            return "salvage-\(result.sourceURL?.path ?? "memory")"
        }
    }

    var title: String {
        switch self {
        case .draft:
            return "Recover Unsaved Sketch?"
        case .salvage:
            return "Recover Damaged Sketch?"
        }
    }

    var message: String {
        switch self {
        case .draft(let record, _):
            let when = record.savedAt.formatted(date: .abbreviated, time: .shortened)
            return "Geometry Studio found unsaved changes from \(when). Recovering keeps the sketch open so you can review it and save."
        case .salvage(let result):
            return "Geometry Studio could read \(result.recovered) of \(result.total) objects in this file. Save the recovered sketch under a new name before making changes."
        }
    }
}

struct DraftRecord: Codable {
    var savedAt: Date
    var document: SketchDocument
    var sourceURL: URL?
}

/// Autosave drafts live in Application Support, one file per editing session.
enum DocumentDrafts {
    private static let folderName = "Geometry Studio"
    private static let draftsFolderName = "Drafts"
    private static let fileExtension = "gspdraft"

    static func write(_ record: DraftRecord, sessionID: UUID) throws {
        let directory = try directory()
        let target = fileURL(for: sessionID, in: directory)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        try data.write(to: target, options: .atomic)
        pruneDrafts(in: directory, keeping: target)
    }

    /// This app edits one document per process, so drafts from earlier
    /// sessions are stale once a new one is written.
    private static func pruneDrafts(in directory: URL, keeping target: URL) {
        // A failed listing only skips this prune; the new draft is already safe.
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory,
                                                                       includingPropertiesForKeys: nil,
                                                                       options: [.skipsHiddenFiles]) else {
            return
        }
        for file in files where file.pathExtension == fileExtension && file != target {
            remove(at: file)
        }
    }

    /// The most recently written draft, if there is one.
    static func latest() -> (DraftRecord, URL)? {
        guard let directory = try? directory(),
              let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
              ) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var best: (DraftRecord, URL, Date)?
        for file in files where file.pathExtension == fileExtension {
            // A damaged draft must not block launch; skip it.
            guard let data = try? Data(contentsOf: file),
                  let record = try? decoder.decode(DraftRecord.self, from: data),
                  let date = try? file.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate else {
                continue
            }
            if let best, date <= best.2 {
                continue
            }
            best = (record, file, date)
        }
        guard let best else { return nil }
        return (best.0, best.1)
    }

    static func remove(at url: URL) {
        // A draft is disposable; a failed delete only costs a stale offer.
        try? FileManager.default.removeItem(at: url)
    }

    static func remove(sessionID: UUID) {
        // Without the drafts folder there is nothing to delete.
        guard let directory = try? directory() else { return }
        remove(at: fileURL(for: sessionID, in: directory))
    }

    private static func directory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory,
                                               in: .userDomainMask,
                                               appropriateFor: nil,
                                               create: true)
        let directory = base
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent(draftsFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func fileURL(for sessionID: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent("\(sessionID.uuidString).\(fileExtension)")
    }
}
