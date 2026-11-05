import Foundation

enum FactSensitivity: String, Codable, Sendable, Equatable {
    case family
    case sealed
}

struct FamilyFact: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var room: String?
    var device: String?
    var action: String?
    var time: Date?
    var source: EventSource
    var text: String
    var sensitivity: FactSensitivity
    var origin: FamilyMessageKind

    init(id: UUID = UUID(),
         room: String? = nil,
         device: String? = nil,
         action: String? = nil,
         time: Date? = nil,
         source: EventSource,
         text: String,
         sensitivity: FactSensitivity = .family,
         origin: FamilyMessageKind = .fact) {
        self.id = id
        self.room = room
        self.device = device
        self.action = action
        self.time = time
        self.source = source
        self.text = text
        self.sensitivity = sensitivity
        self.origin = origin
    }
}

protocol FamilyFactExtracting: Sendable {
    func extract(from text: String, now: Date, source: EventSource, calendar: Calendar) -> [FamilyFact]
    func extract(event: SpaceEvent) -> FamilyFact
}

/// Rule extractor for MVP-1. A model channel can sit beside this later. It never promotes a confession.
struct RuleBasedFamilyFactExtractor: FamilyFactExtracting {
    func extract(from text: String, now: Date, source: EventSource, calendar: Calendar = .current) -> [FamilyFact] {
        let folded = text.lowercased()
        if Self.isSealed(folded) { return [] }
        var scratch = folded
        let room = Self.firstMatch(in: folded, phrases: Self.rooms)
        let device = Self.firstMatch(in: folded, phrases: Self.devices)
        if let phrase = room?.phrase { scratch = scratch.replacingOccurrences(of: phrase, with: " ") }
        if let phrase = device?.phrase { scratch = scratch.replacingOccurrences(of: phrase, with: " ") }
        let action = Self.firstMatch(in: scratch, phrases: Self.actions)
        let measurement = Self.hasMeasurement(folded)
        guard room != nil || device != nil else { return [] }
        guard action != nil || measurement else { return [] }
        let fact = FamilyFact(
            room: room?.id,
            device: device?.id,
            action: action?.id ?? (measurement ? "set" : nil),
            time: Self.clock(in: folded, on: now, calendar: calendar) ?? now,
            source: source,
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            sensitivity: .family,
            origin: .fact
        )
        return [fact]
    }

    func extract(event: SpaceEvent) -> FamilyFact {
        FamilyFact(
            id: UUID(uuidString: event.id) ?? UUID(),
            room: event.roomID,
            device: event.deviceID,
            action: event.action,
            time: event.occurredAt,
            source: event.source,
            text: event.detail.en,
            sensitivity: .family,
            origin: .event
        )
    }

    static func isSealed(_ folded: String) -> Bool {
        let needles = ["秘密", "难过", "伤心", "抑郁", "倾诉", "分手", "不想活", "自杀", "哭了",
                       "secret", "confidential", "depressed", "suicide", "kill myself", "heartbroken",
                       "i feel sad", "i'm sad", "im sad"]
        return needles.contains { folded.contains($0) }
    }

    private struct Hit {
        var id: String
        var phrase: String
    }

    private static func firstMatch(in text: String, phrases: [(String, String)]) -> Hit? {
        for (phrase, id) in phrases where text.contains(phrase) {
            return Hit(id: id, phrase: phrase)
        }
        return nil
    }

    private static func hasMeasurement(_ text: String) -> Bool {
        if text.contains("°c") || text.contains("℃") || text.contains("湿度") || text.contains("humidity") {
            return true
        }
        if text.contains("度") && text.contains(where: \.isNumber) { return true }
        if text.contains("风速") || text.contains("fan") { return true }
        return false
    }

    static func clock(in text: String, on day: Date, calendar: Calendar) -> Date? {
        let scalars = Array(text)
        var index = 0
        while index < scalars.count {
            if scalars[index].isNumber {
                var hour = ""
                var cursor = index
                while cursor < scalars.count, scalars[cursor].isNumber, hour.count < 2 {
                    hour.append(scalars[cursor])
                    cursor += 1
                }
                if cursor < scalars.count, scalars[cursor] == Character(":"), let hourValue = Int(hour), (0...23).contains(hourValue) {
                    cursor += 1
                    var minute = ""
                    while cursor < scalars.count, scalars[cursor].isNumber, minute.count < 2 {
                        minute.append(scalars[cursor])
                        cursor += 1
                    }
                    if minute.count == 2, let minuteValue = Int(minute), (0...59).contains(minuteValue) {
                        var parts = calendar.dateComponents([.year, .month, .day], from: day)
                        parts.hour = hourValue
                        parts.minute = minuteValue
                        parts.second = 0
                        return calendar.date(from: parts)
                    }
                }
            }
            index += 1
        }
        return nil
    }

    /// Longest phrases first so 吊灯 wins over 灯 and 打开 wins over 开.
    private static let rooms: [(String, String)] = [
        ("living room", "living_room"),
        ("dining room", "dining_room"),
        ("客厅", "living_room"),
        ("餐厅", "dining_room"),
        ("卧室", "bedroom"),
        ("厨房", "kitchen"),
        ("书房", "study"),
        ("卫生间", "bathroom")
    ]

    private static let devices: [(String, String)] = [
        ("air conditioner", "air_conditioner"),
        ("wall switch", "wall_switch"),
        ("pendant", "pendant_light"),
        ("吊灯", "pendant_light"),
        ("墙面开关", "wall_switch"),
        ("空调", "air_conditioner"),
        ("light", "light"),
        ("灯", "light")
    ]

    private static let actions: [(String, String)] = [
        ("turned on", "turn_on"),
        ("turn on", "turn_on"),
        ("turned off", "turn_off"),
        ("turn off", "turn_off"),
        ("switch off", "turn_off"),
        ("switch on", "turn_on"),
        ("set to", "set"),
        ("打开", "turn_on"),
        ("关掉", "turn_off"),
        ("关闭", "turn_off"),
        ("调为", "set"),
        ("调到", "set"),
        ("设为", "set")
    ]
}
