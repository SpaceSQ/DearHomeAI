import Foundation

/// Sample day from the house notebook: living room at 07:00, dining room at 11:15.
struct MockHomeProvider: HomeKitBridging {
    func currentAuthorization() async -> HomeAuthorizationState { .mock }

    func loadSnapshot() async -> HomeSnapshot {
        snapshot(now: Date())
    }

    func suggestion(for event: SpaceEvent) async -> HomeControlSuggestion {
        HomeSuggestions.make(for: event)
    }

    func performWrite(accessoryID: String, powerOn: Bool) async throws {
        throw HomeKitControlError.suggestOnly
    }

    func snapshot(now: Date, calendar: Calendar = .current) -> HomeSnapshot {
        let morning = Self.clock(hour: 7, minute: 0, on: now, calendar: calendar)
        let pendantOn = Self.clock(hour: 7, minute: 5, on: now, calendar: calendar)
        let pendantOff = Self.clock(hour: 7, minute: 15, on: now, calendar: calendar)
        let dining = Self.clock(hour: 11, minute: 15, on: now, calendar: calendar)

        let living = HomeRoom(
            id: "living_room",
            name: Bilingual(en: "Living room", zh: "客厅"),
            accessories: [
                HomeAccessory(id: "living.ac", name: Bilingual(en: "Air conditioner", zh: "空调"),
                              kind: .airConditioner, isOn: true, temperatureC: 25, humidity: 0.60, fanSpeed: 1),
                HomeAccessory(id: "living.pendant", name: Bilingual(en: "Pendant light", zh: "吊灯"),
                              kind: .pendantLight, isOn: false, temperatureC: nil, humidity: nil, fanSpeed: nil),
                HomeAccessory(id: "living.switch", name: Bilingual(en: "Wall switch", zh: "墙面开关"),
                              kind: .wallSwitch, isOn: false, temperatureC: nil, humidity: nil, fanSpeed: nil)
            ]
        )
        let diningRoom = HomeRoom(
            id: "dining_room",
            name: Bilingual(en: "Dining room", zh: "餐厅"),
            accessories: [
                HomeAccessory(id: "dining.light", name: Bilingual(en: "Dining light", zh: "餐厅灯"),
                              kind: .light, isOn: true, temperatureC: nil, humidity: nil, fanSpeed: nil)
            ]
        )
        let events = [
            SpaceEvent(
                id: "sample-living-climate",
                roomID: living.id,
                roomName: living.name,
                title: Bilingual(en: "Climate set", zh: "气候调好了"),
                detail: Bilingual(
                    en: "Living room set to 25°C, humidity 60%, fan speed 1.",
                    zh: "客厅空间调为 25°C，湿度 60%，风速 1 档。"
                ),
                occurredAt: morning,
                source: .appleHome,
                sourceLabel: Bilingual(en: "Apple Home", zh: "Apple 智能家居"),
                deviceID: "living.ac",
                action: "set"
            ),
            SpaceEvent(
                id: "sample-pendant-on",
                roomID: living.id,
                roomName: living.name,
                title: Bilingual(en: "Pendant light on", zh: "主人打开吊灯"),
                detail: Bilingual(en: "The owner turned the pendant light on.", zh: "主人打开吊灯。"),
                occurredAt: pendantOn,
                source: .familyApp,
                sourceLabel: Bilingual(en: "Dad's app", zh: "爸爸 APP"),
                deviceID: "living.pendant",
                action: "turn_on"
            ),
            SpaceEvent(
                id: "sample-pendant-off",
                roomID: living.id,
                roomName: living.name,
                title: Bilingual(en: "Wall switch closed the light", zh: "墙面开关关掉吊灯"),
                detail: Bilingual(en: "The wall switch turned the pendant light off.", zh: "墙面开关关掉了吊灯。"),
                occurredAt: pendantOff,
                source: .homeAgent,
                sourceLabel: Bilingual(en: "Smart home agent", zh: "家居智能体"),
                deviceID: "living.switch",
                action: "turn_off"
            ),
            SpaceEvent(
                id: "sample-dining-voice",
                roomID: diningRoom.id,
                roomName: diningRoom.name,
                title: Bilingual(en: "Dining light on", zh: "餐厅灯打开"),
                detail: Bilingual(en: "The dining room light was opened by voice.", zh: "餐厅灯由女儿语音控制打开。"),
                occurredAt: dining,
                source: .voice,
                sourceLabel: Bilingual(en: "Daughter's voice", zh: "女儿语音"),
                deviceID: "dining.light",
                action: "turn_on"
            )
        ]
        return HomeSnapshot(
            rooms: [living, diningRoom],
            scenes: [
                HomeScene(id: "scene.morning", name: Bilingual(en: "Morning living room", zh: "清晨客厅"), suggestOnly: true),
                HomeScene(id: "scene.dining", name: Bilingual(en: "Dining light", zh: "餐厅开灯"), suggestOnly: true)
            ],
            events: events,
            authorization: .mock,
            isMock: true,
            status: Bilingual(
                en: "Sample rooms from the house notebook. Apple Home is not connected.",
                zh: "这是手记里的示例房间。还没有连接 Apple Home。"
            )
        )
    }

    private static func clock(hour: Int, minute: Int, on day: Date, calendar: Calendar) -> Date {
        var parts = calendar.dateComponents([.year, .month, .day], from: day)
        parts.hour = hour
        parts.minute = minute
        parts.second = 0
        return calendar.date(from: parts) ?? day
    }
}
