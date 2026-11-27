import Foundation

enum TransformKind: String, Codable, CaseIterable, Identifiable {
    case reflect
    case rotate
    case translate
    case dilate
    var id: String {
        rawValue
    }
    var title: String {
        rawValue.capitalized
    }
}
