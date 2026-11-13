import ActivityKit
import Foundation

struct MaskAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var width: MaskWidth?

        init(width: MaskWidth = .standard) {
            self.width = width
        }

        // Version 1.0 stored an empty object. Existing activities adopt the new default.
        var effectiveWidth: MaskWidth { width ?? .standard }
    }

    let startedAt: Date
}

enum MaskWidth: String, Codable, CaseIterable, Identifiable {
    case narrow, standard, wide

    var id: String { rawValue }

    var title: String {
        switch self {
        case .narrow: return "较窄"
        case .standard: return "标准"
        case .wide: return "加宽"
        }
    }

    var sideWidth: Double {
        switch self {
        case .narrow: return 9
        case .standard: return 15
        case .wide: return 21
        }
    }
}
