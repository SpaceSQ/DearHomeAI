import Foundation

enum SyncMode: String, Codable, Sendable, Equatable, CaseIterable, Identifiable {
    case dailyMidnight
    case realtime

    var id: String { rawValue }

    func title(in language: ContentLanguage) -> String {
        switch self {
        case .dailyMidnight: return tr("Daily at 00:00", "每日 00:00", language: language)
        case .realtime: return tr("Realtime", "实时", language: language)
        }
    }
}

enum FamilyMessageKind: String, Codable, Sendable, Equatable {
    case fact
    case event
    case digest
}

struct FamilyPayload: Codable, Equatable, Sendable {
    var text: String
    var room: String?
    var device: String?
    var action: String?
    var factTime: Date?
}

struct FamilyMessageEnvelope: Codable, Equatable, Sendable, Identifiable {
    var familyId: String
    var msgId: UUID
    var ts: Date
    var kind: FamilyMessageKind
    var room: String?
    var source: EventSource
    var payload: FamilyPayload
    var syncMode: SyncMode
    var sensitivity: FactSensitivity

    var id: UUID { msgId }

    init(familyId: String,
         msgId: UUID = UUID(),
         ts: Date,
         kind: FamilyMessageKind,
         room: String?,
         source: EventSource,
         payload: FamilyPayload,
         syncMode: SyncMode,
         sensitivity: FactSensitivity = .family) {
        self.familyId = familyId
        self.msgId = msgId
        self.ts = FamilyDateFormat.normalized(ts)
        self.kind = kind
        self.room = room
        self.source = source
        self.payload = payload
        self.syncMode = syncMode
        self.sensitivity = sensitivity
    }

    enum CodingKeys: String, CodingKey {
        case familyId, msgId, ts, kind, room, source, payload, syncMode, sensitivity
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        familyId = try box.decode(String.self, forKey: .familyId)
        msgId = try box.decode(UUID.self, forKey: .msgId)
        ts = try box.decode(Date.self, forKey: .ts)
        kind = try box.decode(FamilyMessageKind.self, forKey: .kind)
        room = try box.decodeIfPresent(String.self, forKey: .room)
        source = try box.decode(EventSource.self, forKey: .source)
        payload = try box.decode(FamilyPayload.self, forKey: .payload)
        syncMode = try box.decode(SyncMode.self, forKey: .syncMode)
        sensitivity = try box.decodeIfPresent(FactSensitivity.self, forKey: .sensitivity) ?? .family
    }

    func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(familyId, forKey: .familyId)
        try box.encode(msgId, forKey: .msgId)
        try box.encode(ts, forKey: .ts)
        try box.encode(kind, forKey: .kind)
        try box.encodeIfPresent(room, forKey: .room)
        try box.encode(source, forKey: .source)
        try box.encode(payload, forKey: .payload)
        try box.encode(syncMode, forKey: .syncMode)
        try box.encode(sensitivity, forKey: .sensitivity)
    }
}

enum FamilyJSON {
    static func encode(_ envelope: FamilyMessageEnvelope) throws -> Data {
        try JSONCoding.fractionalDateEncoder().encode(envelope)
    }

    static func decode(_ data: Data) throws -> FamilyMessageEnvelope {
        try JSONCoding.fractionalDateDecoder().decode(FamilyMessageEnvelope.self, from: data)
    }
}

enum FamilyTransport {
    /// Real broker binary is MVP-2. Keep this false so the app never tries to bind a port.
    static let usesEmbeddedBroker = false
    static let bonjourType = "_mqtt._tcp"
}
