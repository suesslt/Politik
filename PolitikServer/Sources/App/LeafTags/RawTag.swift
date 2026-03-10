import LeafKit
import Vapor

/// A Leaf tag that outputs HTML content without escaping.
/// Usage: #raw(variable)
struct RawTag: UnsafeUnescapedLeafTag {
    static let name = "raw"

    func render(_ ctx: LeafContext) throws -> LeafData {
        guard let html = ctx.parameters.first?.string else {
            return .string("")
        }
        return .string(html)
    }
}
