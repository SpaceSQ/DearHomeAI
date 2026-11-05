import Foundation

enum JSONCoding {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func fractionalDateEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var box = encoder.singleValueContainer()
            try box.encode(FamilyDateFormat.string(from: date))
        }
        return encoder
    }

    static func fractionalDateDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let box = try decoder.singleValueContainer()
            let raw = try box.decode(String.self)
            guard let date = FamilyDateFormat.date(from: raw) else {
                throw DecodingError.dataCorruptedError(in: box, debugDescription: "bad date \(raw)")
            }
            return date
        }
        return decoder
    }
}

enum FamilyDateFormat {
    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func date(from raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    /// Millisecond precision so encode/decode equality holds.
    static func normalized(_ date: Date) -> Date {
        let milliseconds = (date.timeIntervalSince1970 * 1000).rounded() / 1000
        return Date(timeIntervalSince1970: milliseconds)
    }
}
