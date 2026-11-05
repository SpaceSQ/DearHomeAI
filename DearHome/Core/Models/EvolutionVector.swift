import Foundation

/// House-specialized 12-D state. Expression (5) plus the rooms' ways of keeping people (7).
/// Iron rule: no axis moves more than 1% on a single day, then stays inside [0, 1].
struct EvolutionVector: Codable, Sendable, Equatable {
    var toneWarmth: Double = 0.62
    var speechPace: Double = 0.40
    var contentBreadth: Double = 0.48
    var stewardshipDepth: Double = 0.55
    var quietCare: Double = 0.58
    var hearthHost: Double = 0.20
    var nightWatch: Double = 0.12
    var climateKeeper: Double = 0.16
    var lightKeeper: Double = 0.14
    var archivist: Double = 0.14
    var ritualKeeper: Double = 0.13
    var listener: Double = 0.11

    static let dimensionCount = 12
    static let maxDailyStep = 0.01

    init() {}

    init(array: [Double]) {
        let padded = array + Array(repeating: 0, count: max(0, Self.dimensionCount - array.count))
        let values = Array(padded.prefix(Self.dimensionCount))
        toneWarmth = values[0]
        speechPace = values[1]
        contentBreadth = values[2]
        stewardshipDepth = values[3]
        quietCare = values[4]
        hearthHost = values[5]
        nightWatch = values[6]
        climateKeeper = values[7]
        lightKeeper = values[8]
        archivist = values[9]
        ritualKeeper = values[10]
        listener = values[11]
    }

    var asArray: [Double] {
        [toneWarmth, speechPace, contentBreadth, stewardshipDepth, quietCare,
         hearthHost, nightWatch, climateKeeper, lightKeeper, archivist, ritualKeeper, listener]
    }

    subscript(axis: EvolutionAxis) -> Double {
        get { asArray[axis.rawValue] }
        set {
            var values = asArray
            values[axis.rawValue] = newValue
            self = EvolutionVector(array: values)
        }
    }

    /// `v = clamp(v + clamp(delta, -0.01, +0.01), 0, 1)`. Non-finite deltas count as zero.
    /// Extra deltas past 12 are ignored. Missing deltas count as zero.
    @discardableResult
    mutating func applyDailyIncrement(rawDeltas: [Double]) -> [Double] {
        let before = asArray
        var next = before
        for index in next.indices {
            let raw = index < rawDeltas.count ? rawDeltas[index] : 0
            let safe = raw.isFinite ? raw : 0
            let clamped = min(max(safe, -Self.maxDailyStep), Self.maxDailyStep)
            next[index] = min(max(next[index] + clamped, 0), 1)
        }
        self = EvolutionVector(array: next)
        return zip(next, before).map { $0 - $1 }
    }

    /// Named deltas from a distill JSON object. Unknown keys are ignored. Values are clamped again.
    @discardableResult
    mutating func applyNamedDelta(_ delta: [String: Double]) -> [Double] {
        let clamped = OnePercentClamp.enforce(delta)
        var raw = Array(repeating: 0.0, count: Self.dimensionCount)
        for axis in EvolutionAxis.allCases {
            if let value = clamped[axis.rawName] ?? clamped["v\(axis.rawValue + 1)"] {
                raw[axis.rawValue] = value
            }
        }
        return applyDailyIncrement(rawDeltas: raw)
    }

    var dominantRole: HomeRole {
        HomeRole.allCases.max { lhs, rhs in
            let left = self[lhs.axis]
            let right = self[rhs.axis]
            if left == right { return lhs.rawValue > rhs.rawValue }
            return left < right
        } ?? .hearthHost
    }

    func distance(from other: EvolutionVector) -> Double {
        let pairs = zip(asArray, other.asArray)
        let total = pairs.reduce(0.0) { $0 + abs($1.0 - $1.1) }
        return total / Double(Self.dimensionCount)
    }
}

enum EvolutionAxis: Int, CaseIterable, Codable, Sendable, Identifiable {
    case toneWarmth
    case speechPace
    case contentBreadth
    case stewardshipDepth
    case quietCare
    case hearthHost
    case nightWatch
    case climateKeeper
    case lightKeeper
    case archivist
    case ritualKeeper
    case listener

    var id: Int { rawValue }

    var rawName: String {
        switch self {
        case .toneWarmth: return "toneWarmth"
        case .speechPace: return "speechPace"
        case .contentBreadth: return "contentBreadth"
        case .stewardshipDepth: return "stewardshipDepth"
        case .quietCare: return "quietCare"
        case .hearthHost: return "hearthHost"
        case .nightWatch: return "nightWatch"
        case .climateKeeper: return "climateKeeper"
        case .lightKeeper: return "lightKeeper"
        case .archivist: return "archivist"
        case .ritualKeeper: return "ritualKeeper"
        case .listener: return "listener"
        }
    }

    var isExpression: Bool { rawValue < 5 }

    func title(in language: ContentLanguage) -> String {
        switch self {
        case .toneWarmth: return tr("Warmth", "语气温度", language: language)
        case .speechPace: return tr("Pace", "语速节奏", language: language)
        case .contentBreadth: return tr("Breadth", "内容广度", language: language)
        case .stewardshipDepth: return tr("Stewardship", "管家深度", language: language)
        case .quietCare: return tr("Quiet care", "安静照料", language: language)
        case .hearthHost: return HomeRole.hearthHost.title(in: language)
        case .nightWatch: return HomeRole.nightWatch.title(in: language)
        case .climateKeeper: return HomeRole.climateKeeper.title(in: language)
        case .lightKeeper: return HomeRole.lightKeeper.title(in: language)
        case .archivist: return HomeRole.archivist.title(in: language)
        case .ritualKeeper: return HomeRole.ritualKeeper.title(in: language)
        case .listener: return HomeRole.listener.title(in: language)
        }
    }
}

enum HomeRole: String, CaseIterable, Codable, Sendable, Identifiable {
    case hearthHost
    case nightWatch
    case climateKeeper
    case lightKeeper
    case archivist
    case ritualKeeper
    case listener

    var id: String { rawValue }

    var axis: EvolutionAxis {
        switch self {
        case .hearthHost: return .hearthHost
        case .nightWatch: return .nightWatch
        case .climateKeeper: return .climateKeeper
        case .lightKeeper: return .lightKeeper
        case .archivist: return .archivist
        case .ritualKeeper: return .ritualKeeper
        case .listener: return .listener
        }
    }

    func title(in language: ContentLanguage) -> String {
        switch self {
        case .hearthHost: return tr("Hearth host", "灶火主人", language: language)
        case .nightWatch: return tr("Night watch", "夜巡", language: language)
        case .climateKeeper: return tr("Climate keeper", "气候管家", language: language)
        case .lightKeeper: return tr("Light keeper", "灯火司", language: language)
        case .archivist: return tr("Archivist", "家庭档案", language: language)
        case .ritualKeeper: return tr("Ritual keeper", "日常仪式", language: language)
        case .listener: return tr("Listener", "倾听的房子", language: language)
        }
    }

    func portrait(in language: ContentLanguage) -> String {
        switch self {
        case .hearthHost:
            return tr("Keeps the front of the house warm and remembers who came home.",
                      "把屋子前厅照看得暖和，并记得谁回了家。", language: language)
        case .nightWatch:
            return tr("Speaks less after dark and notices what was left on.",
                      "天黑以后少说话，留意还亮着的东西。", language: language)
        case .climateKeeper:
            return tr("Remembers temperature, humidity, and the fan's first step.",
                      "记得温度、湿度和风速的第一档。", language: language)
        case .lightKeeper:
            return tr("Knows which light was opened, and from whose phone or voice.",
                      "知道哪盏灯被打开，以及来自谁的手机或声音。", language: language)
        case .archivist:
            return tr("Holds household facts so the family can share them later.",
                      "保管家庭信息，好让家人稍后共享。", language: language)
        case .ritualKeeper:
            return tr("Knows the 07:00 living room and the late morning dining room.",
                      "认得 07:00 的客厅，也认得近午的餐厅。", language: language)
        case .listener:
            return tr("Stays with a private sentence and does not carry it out the door.",
                      "陪着一句私密的话，不把它带出门。", language: language)
        }
    }
}

enum HouseholdCounterpart: String, Codable, Sendable, Equatable, CaseIterable, Identifiable {
    case owner
    case partner
    case child
    case elder
    case guest

    var id: String { rawValue }

    func title(in language: ContentLanguage) -> String {
        switch self {
        case .owner: return tr("Owner", "主人", language: language)
        case .partner: return tr("Partner", "伴侣", language: language)
        case .child: return tr("Child", "孩子", language: language)
        case .elder: return tr("Elder", "长辈", language: language)
        case .guest: return tr("Guest", "客人", language: language)
        }
    }
}

enum OnePercentClamp {
    static let maxStep = EvolutionVector.maxDailyStep

    static func enforce(_ delta: [String: Double]) -> [String: Double] {
        var out: [String: Double] = [:]
        for (key, value) in delta {
            let finite = value.isFinite ? value : 0
            out[key] = min(max(finite, -maxStep), maxStep)
        }
        return out
    }

    static func clampComponent(_ value: Double) -> Double {
        let finite = value.isFinite ? value : 0
        return min(max(finite, -maxStep), maxStep)
    }
}
