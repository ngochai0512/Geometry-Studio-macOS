import CoreGraphics
import UniformTypeIdentifiers

/// The file formats File ▸ Export offers.
enum SketchExportFormat: String, CaseIterable, Identifiable {
    case pdf
    case svg
    case png

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .pdf: return "PDF"
        case .svg: return "SVG"
        case .png: return "PNG"
        }
    }

    var fileExtension: String {
        rawValue
    }

    var contentType: UTType {
        switch self {
        case .pdf: return .pdf
        case .svg: return .svg
        case .png: return .png
        }
    }
}

enum SketchExportMetrics {
    /// One export canvas for every format: 3:2 crops least badly into papers
    /// (√2, 1.29) and slides (16:9). PNG doubles this in pixels.
    static let size = CGSize(width: 1200, height: 800)
    static let rasterScale: CGFloat = 2
}
