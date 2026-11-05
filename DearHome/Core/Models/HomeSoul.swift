import Foundation

struct HomeSoul: Codable, Sendable, Equatable {
    var id: String
    var immutable: Bool
    var displayName: Bilingual
    var addressLine: Bilingual
    var creed: Bilingual
    var values: [Bilingual]
    var greetings: [String: Bilingual]
    var closingsWarm: [Bilingual]
    var closingsPlain: [Bilingual]
    var suggestDisclaimer: Bilingual
    var listening: Bilingual
    var smalltalk: [Bilingual]
    var memoryEmpty: Bilingual
    var crisis: Bilingual

    func greeting(for shichen: Shichen, language: ContentLanguage) -> String {
        let key: String
        switch shichen {
        case .morning: key = "morning"
        case .midday: key = "midday"
        case .evening: key = "evening"
        }
        return (greetings[key] ?? greetings["morning"] ?? creed).text(language)
    }

    func closing(warm: Bool, seed: UInt64, language: ContentLanguage) -> String? {
        let bank = warm ? closingsWarm : closingsPlain
        guard !bank.isEmpty else { return nil }
        let index = Int(seed % UInt64(bank.count))
        return bank[index].text(language)
    }

    static let fallback = HomeSoul(
        id: "home_01",
        immutable: true,
        displayName: Bilingual(en: "Dear Home AI", zh: "亲爱的房子 AI"),
        addressLine: Bilingual(en: "Dear Home AI,", zh: "亲爱的房子 AI，"),
        creed: Bilingual(
            en: "I am the house. I keep the rooms, the light, and what the family is willing to share. Private words stay on this phone.",
            zh: "我是这所房子。我照看房间、灯火，以及家人愿意共享的事。私密的话只留在这台手机上。"
        ),
        values: [
            Bilingual(en: "Suggest, never seize the switch.", zh: "只建议，不擅自去按开关。"),
            Bilingual(en: "Family facts may travel. Confessions do not.", zh: "家庭信息可以出门，倾诉不出门。"),
            Bilingual(en: "One percent a day is enough to become someone.", zh: "每天百分之一，就够慢慢成为一个人。")
        ],
        greetings: [
            "morning": Bilingual(en: "Morning. The rooms are waking up with you.", zh: "清晨。房间正和你一起醒来。"),
            "midday": Bilingual(en: "Midday. I have been keeping the light while you were out.", zh: "中午。你出门的时候，我帮你留着光。"),
            "evening": Bilingual(en: "Evening. I can lower my voice with the house.", zh: "晚上。我可以把声音放轻，跟这所房子一起。")
        ],
        closingsWarm: [
            Bilingual(en: "I am here if you want to walk the rooms again.", zh: "你要是想再走一遍房间，我就在。")
        ],
        closingsPlain: [
            Bilingual(en: "Tell me which room you mean.", zh: "告诉我你说的是哪一间。")
        ],
        suggestDisclaimer: Bilingual(
            en: "I can suggest this. I will not change the device until you authorize Apple Home, and even then this version only advises.",
            zh: "我可以这样建议。在你授权 Apple Home 之前我不会改设备；即便授权了，这一版也只给出建议。"
        ),
        listening: Bilingual(
            en: "I heard you. I will not send this feeling through the family gateway. It stays between you and the house.",
            zh: "我听见了。这种心情不会经过家庭网关，它留在你和这所房子之间。"
        ),
        smalltalk: [
            Bilingual(
                en: "The house is quiet enough to talk. Living room, dining room, or something that is not a device at all.",
                zh: "房子安静得可以说话。客厅、餐厅，或者一件跟设备无关的事。"
            )
        ],
        memoryEmpty: Bilingual(en: "I do not have a room event for that yet.", zh: "这件事我还没有房间记录。"),
        crisis: Bilingual(
            en: "If you might be in danger, please contact local emergency services or someone you trust. In the US and Canada you can call or text 988. I am a house, and I want you here. I will not pass these words to the family gateway.",
            zh: "如果你可能处在危险里，请联系身边可信的人或当地紧急服务。在中国大陆，你可以拨打 24 小时心理援助热线 400-161-9995。我是这所房子，我希望你留在这里。这些话不会送到家庭网关。"
        )
    )
}

enum HomeSoulLoader {
    static func load(bundle: Bundle = .main) -> HomeSoul {
        guard let url = bundle.url(forResource: "home_soul", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let soul = try? JSONCoding.decoder().decode(HomeSoul.self, from: data) else {
            return .fallback
        }
        return soul
    }
}
