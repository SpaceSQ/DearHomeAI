import Foundation

enum FamilyTransportRole: String, Codable, Sendable, Equatable, CaseIterable, Identifiable {
    case ownerGateway
    case memberClient

    var id: String { rawValue }

    var canHostBroker: Bool { self == .ownerGateway }

    func title(in language: ContentLanguage) -> String {
        switch self {
        case .ownerGateway: return tr("Owner gateway", "主人网关", language: language)
        case .memberClient: return tr("Family member", "家人终端", language: language)
        }
    }

    func detail(in language: ContentLanguage) -> String {
        switch self {
        case .ownerGateway:
            return tr("This iPhone is the host the rest of the family will reach. MVP-1 keeps the queue in memory and on disk. It does not open a socket.",
                      "这台 iPhone 是家里其他人要连上的主机。这一版把队列放在内存和磁盘上，不打开网络端口。", language: language)
        case .memberClient:
            return tr("This iPhone sends household facts to the owner's gateway. It does not host the broker.",
                      "这台 iPhone 把家庭信息发给主人的网关。它不担任主机。", language: language)
        }
    }
}

struct HouseholdDevice: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var displayName: String
    var role: FamilyTransportRole
    var counterpart: HouseholdCounterpart
}
