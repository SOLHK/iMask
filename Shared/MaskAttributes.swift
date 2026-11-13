import ActivityKit
import Foundation

struct MaskAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {}

    let startedAt: Date
}
