import Foundation
import HomeKit

/// Read-only HomeKit bridge. `performWrite` always refuses: MVP-1 is suggest-only.
@MainActor
final class LiveHomeKitBridge: NSObject, HMHomeManagerDelegate {
    private let manager: HMHomeManager
    private var didUpdate = false
    private var homesWait: CheckedContinuation<Void, Never>?

    override init() {
        let manager = HMHomeManager()
        self.manager = manager
        super.init()
        manager.delegate = self
    }

    @objc nonisolated func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        Task { @MainActor in
            self.finishWait()
        }
    }

    private func finishWait() {
        didUpdate = true
        if let homesWait {
            self.homesWait = nil
            homesWait.resume()
        }
    }

    private func waitForFirstUpdate() async {
        if didUpdate { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if didUpdate {
                continuation.resume()
                return
            }
            homesWait = continuation
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                self.finishWait()
            }
        }
    }
}

extension LiveHomeKitBridge: HomeKitBridging {
    nonisolated func currentAuthorization() async -> HomeAuthorizationState {
        await mappedAuthorization()
    }

    nonisolated func loadSnapshot() async -> HomeSnapshot {
        await makeSnapshot()
    }

    nonisolated func suggestion(for event: SpaceEvent) async -> HomeControlSuggestion {
        HomeSuggestions.make(for: event)
    }

    nonisolated func performWrite(accessoryID: String, powerOn: Bool) async throws {
        _ = accessoryID
        _ = powerOn
        throw HomeKitControlError.suggestOnly
    }
}

private extension LiveHomeKitBridge {
    func mappedAuthorization() -> HomeAuthorizationState {
        // HMHomeManagerAuthorizationStatus is an OptionSet (.determined / .restricted / .authorized).
        let status = manager.authorizationStatus
        if status.contains(.authorized) { return .authorized }
        if status.contains(.restricted) { return .restricted }
        if !status.contains(.determined) { return .notDetermined }
        return .restricted
    }

    func makeSnapshot() async -> HomeSnapshot {
        await waitForFirstUpdate()
        let authorization = mappedAuthorization()
        guard authorization == .authorized else {
            return HomeSnapshot(
                rooms: [],
                scenes: [],
                events: [],
                authorization: authorization,
                isMock: false,
                status: Bilingual(
                    en: "Apple Home has not allowed Dear Home to read the house yet.",
                    zh: "Apple Home 还没有允许亲爱的房子读取这所房子。"
                )
            )
        }
        var rooms: [HomeRoom] = []
        var scenes: [HomeScene] = []
        var events: [SpaceEvent] = []
        let now = Date()
        for home in manager.homes {
            var homeRooms = home.rooms
            // On this SDK, roomForEntireHome() is a method returning HMRoom.
            let entireHome = home.roomForEntireHome()
            if !homeRooms.contains(where: { $0.uniqueIdentifier == entireHome.uniqueIdentifier }) {
                homeRooms.insert(entireHome, at: 0)
            }
            for room in homeRooms {
                let accessories = room.accessories.map { accessory in
                    self.accessory(from: accessory)
                }
                let name = room.name
                let model = HomeRoom(
                    id: room.uniqueIdentifier.uuidString,
                    name: Bilingual(en: name, zh: name),
                    accessories: accessories
                )
                rooms.append(model)
                for accessory in room.accessories {
                    events.append(event(from: accessory, room: model, now: now))
                }
            }
            for actionSet in home.actionSets {
                scenes.append(HomeScene(
                    id: actionSet.uniqueIdentifier.uuidString,
                    name: Bilingual(en: actionSet.name, zh: actionSet.name),
                    suggestOnly: true
                ))
            }
        }
        let status: Bilingual
        if rooms.isEmpty {
            status = Bilingual(
                en: "Apple Home is authorized and has no rooms yet. Current readings appear here when it does. This is not yesterday's story.",
                zh: "已授权 Apple Home，但还没有房间。有读数时会显示在这里。这不是昨天的故事。"
            )
        } else {
            status = Bilingual(
                en: "Current Apple Home readings. HomeKit does not give Dear Home the morning's history.",
                zh: "这是 Apple Home 的当前读数。HomeKit 不会把清晨的历史交给亲爱的房子。"
            )
        }
        return HomeSnapshot(rooms: rooms, scenes: scenes, events: events,
                            authorization: .authorized, isMock: false, status: status)
    }

    func accessory(from accessory: HMAccessory) -> HomeAccessory {
        let name = accessory.name
        return HomeAccessory(
            id: accessory.uniqueIdentifier.uuidString,
            name: Bilingual(en: name, zh: name),
            kind: kind(of: accessory),
            isOn: boolValue(accessory, HMCharacteristicTypePowerState),
            temperatureC: number(accessory, HMCharacteristicTypeCurrentTemperature)
                ?? number(accessory, HMCharacteristicTypeTargetTemperature),
            humidity: number(accessory, HMCharacteristicTypeCurrentRelativeHumidity),
            fanSpeed: number(accessory, HMCharacteristicTypeRotationSpeed).map { Int($0.rounded()) }
        )
    }

    func event(from accessory: HMAccessory, room: HomeRoom, now: Date) -> SpaceEvent {
        let model = self.accessory(from: accessory)
        var bits: [String] = []
        if let on = model.isOn { bits.append(on ? "on" : "off") }
        if let temperature = model.temperatureC { bits.append(String(format: "%.0f°C", temperature)) }
        if let humidity = model.humidity { bits.append(String(format: "%.0f%%", humidity <= 1 ? humidity * 100 : humidity)) }
        if let fan = model.fanSpeed { bits.append("fan \(fan)") }
        let detail = bits.isEmpty ? accessory.name : bits.joined(separator: " · ")
        return SpaceEvent(
            id: "live-\(accessory.uniqueIdentifier.uuidString)",
            roomID: room.id,
            roomName: room.name,
            title: model.name,
            detail: Bilingual(en: detail, zh: detail),
            occurredAt: now,
            source: .appleHome,
            sourceLabel: Bilingual(en: "Apple Home", zh: "Apple 智能家居"),
            deviceID: model.id,
            action: model.isOn == true ? "turn_on" : (model.isOn == false ? "turn_off" : nil)
        )
    }

    func kind(of accessory: HMAccessory) -> AccessoryKind {
        let types = Set(accessory.services.map(\.serviceType))
        if types.contains(HMServiceTypeThermostat) || types.contains(HMServiceTypeHeaterCooler) || types.contains(HMServiceTypeFan) {
            return .airConditioner
        }
        if types.contains(HMServiceTypeLightbulb) { return .light }
        if types.contains(HMServiceTypeSwitch) { return .wallSwitch }
        return .other
    }

    func number(_ accessory: HMAccessory, _ type: String) -> Double? {
        for service in accessory.services {
            if let characteristic = service.characteristics.first(where: { $0.characteristicType == type }),
               let value = characteristic.value as? NSNumber {
                return value.doubleValue
            }
        }
        return nil
    }

    func boolValue(_ accessory: HMAccessory, _ type: String) -> Bool? {
        for service in accessory.services {
            if let characteristic = service.characteristics.first(where: { $0.characteristicType == type }),
               let value = characteristic.value as? NSNumber {
                return value.boolValue
            }
        }
        return nil
    }
}
