import Foundation

enum StableHash {
    static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }
}

enum CharBudget {
    static func limit(_ text: String, to count: Int) -> String {
        guard count >= 0 else { return "" }
        if text.count <= count { return text }
        return String(text.prefix(count))
    }
}
