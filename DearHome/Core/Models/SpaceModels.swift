import Foundation

enum AccessoryKind: String, Codable, Sendable, Equatable {
    case airConditioner
    case light
    case pendantLight
    case wallSwitch
    case speaker
    case other
}

struct HomeAccessory: Identifiable, Codable, Sendable, Equatable {
    var id: String
    var name: Bilingual
    var kind: AccessoryKind
    var isOn: Bool?
    var temperatureC: Double?
    var humidity: Double?
    var fanSpeed: Int?
}

struct HomeRoom: Identifiable, Codable, Sendable, Equatable {
    var id: String
    var name: Bilingual
    var accessories: [HomeAccessory]
}

struct HomeScene: Identifiable, Codable, Sendable, Equatable {
    var id: String
    var name: Bilingual
    var suggestOnly: Bool
}

struct SpaceEvent: Identifiable, Codable, Sendable, Equatable {
    var id: String
    var roomID: String
    var roomName: Bilingual
    var title: Bilingual
    var detail: Bilingual
    var occurredAt: Date
    var source: EventSource
    var sourceLabel: Bilingual
    var deviceID: String?
    var action: String?
}

struct HomeSnapshot: Sendable, Equatable {
    var rooms: [HomeRoom]
    var scenes: [HomeScene]
    var events: [SpaceEvent]
    var authorization: HomeAuthorizationState
    var isMock: Bool
    var status: Bilingual

    static let empty = HomeSnapshot(
        rooms: [],
        scenes: [],
        events: [],
        authorization: .notDetermined,
        isMock: false,
        status: Bilingual(en: "", zh: "")
    )
}

enum HomeAuthorizationState: String, Codable, Sendable, Equatable {
    case notDetermined
    case authorized
    case restricted
    case mock
}

struct HomeControlSuggestion: Sendable, Equatable {
    var title: Bilingual
    var detail: Bilingual
    /// MVP-1 never writes a characteristic. The flag is part of the contract.
    var suggestOnly: Bool = true
}

enum HomeKitControlError: Error, Equatable, Sendable {
    case suggestOnly
    case notAuthorized
}

enum HomeSuggestions {
    static func make(for event: SpaceEvent) -> HomeControlSuggestion {
        HomeControlSuggestion(
            title: Bilingual(
                en: "Suggestion only",
                zh: "仅建议"
            ),
            detail: Bilingual(
                en: "Leave \(event.title.en) as it is, or change it yourself in Apple Home. Dear Home will not press this control in this version.",
                zh: "可以保持「\(event.title.zh)」现状，或你自己在 Apple Home 里改。这一版的亲爱的房子不会去按这个控制。"
            )
        )
    }
}
