import BackgroundTasks
import Foundation

/// Registers the 00:00 catch-up. If the phone is asleep, the next launch runs the same coordinator.
@MainActor
enum MidnightTaskRegistrar {
    static let identifier = "com.s2.dearhome.midnight-distillation"
    private static var didRegister = false
    private static weak var model: AppModel?

    static func register(model: AppModel) {
        self.model = model
        guard !didRegister else { return }
        didRegister = true
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            let box = TaskBox(task)
            Task { @MainActor in
                await MidnightTaskRegistrar.model?.runCatchUp()
                box.task.setTaskCompleted(success: true)
            }
        }
    }

    static func scheduleNext(now: Date = Date(), calendar: Calendar = .current) {
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        let start = calendar.startOfDay(for: now)
        request.earliestBeginDate = calendar.date(byAdding: .day, value: 1, to: start)
        try? BGTaskScheduler.shared.submit(request)
    }
}

private final class TaskBox: @unchecked Sendable {
    let task: BGTask
    init(_ task: BGTask) { self.task = task }
}
