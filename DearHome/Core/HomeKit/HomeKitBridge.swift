import Foundation

protocol HomeKitBridging: Sendable {
    func currentAuthorization() async -> HomeAuthorizationState
    func loadSnapshot() async -> HomeSnapshot
    func suggestion(for event: SpaceEvent) async -> HomeControlSuggestion
    func performWrite(accessoryID: String, powerOn: Bool) async throws
}
