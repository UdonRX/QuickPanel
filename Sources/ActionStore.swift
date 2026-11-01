import Foundation
import Combine

@MainActor
final class ActionStore: ObservableObject {
    @Published private(set) var workflows: [ActionWorkflow] = []
    @Published private(set) var logs: [ActionExecutionLog] = []

    private let workflowsKey = "QuickPanel.ActionWorkflows.v1"
    private let logsKey = "QuickPanel.ActionExecutionLogs.v1"
    private let maximumLogCount = 300

    init() {
        load()
    }

    func load() {
        let defaults = UserDefaults.standard

        if let data = defaults.data(forKey: workflowsKey),
           let decoded = try? JSONDecoder().decode([ActionWorkflow].self, from: data) {
            workflows = decoded
        }

        if let data = defaults.data(forKey: logsKey),
           let decoded = try? JSONDecoder().decode([ActionExecutionLog].self, from: data) {
            logs = decoded
        }
    }

    func saveWorkflow(_ workflow: ActionWorkflow) {
        var updated = workflow
        updated.touch()

        if let index = workflows.firstIndex(where: { $0.id == updated.id }) {
            workflows[index] = updated
        } else {
            workflows.append(updated)
        }
        persistWorkflows()
    }

    func duplicateWorkflow(_ workflow: ActionWorkflow) -> ActionWorkflow {
        var copy = workflow
        copy.id = UUID()
        copy.title += " コピー"
        copy.createdAt = Date()
        copy.updatedAt = Date()
        copy.actions = workflow.actions.map { action in
            var duplicate = action
            duplicate.id = UUID()
            return duplicate
        }
        workflows.append(copy)
        persistWorkflows()
        return copy
    }

    func deleteWorkflow(id: UUID) {
        workflows.removeAll { $0.id == id }
        persistWorkflows()
    }

    func appendLog(_ log: ActionExecutionLog) {
        logs.insert(log, at: 0)
        if logs.count > maximumLogCount {
            logs = Array(logs.prefix(maximumLogCount))
        }
        persistLogs()
    }

    func clearLogs() {
        logs.removeAll()
        persistLogs()
    }

    func workflow(id: UUID) -> ActionWorkflow? {
        workflows.first { $0.id == id }
    }

    private func persistWorkflows() {
        guard let data = try? JSONEncoder().encode(workflows) else { return }
        UserDefaults.standard.set(data, forKey: workflowsKey)
    }

    private func persistLogs() {
        guard let data = try? JSONEncoder().encode(logs) else { return }
        UserDefaults.standard.set(data, forKey: logsKey)
    }
}
