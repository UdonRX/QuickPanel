import Foundation

enum ActionExecutionStatus: String, Codable {
    case success
    case failure
    case skipped
    case completedWithErrors
}

struct ActionExecutionLog: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var workflowID: UUID
    var actionID: UUID?
    var workflowTitle: String
    var actionTitle: String
    var status: ActionExecutionStatus
    var message: String
    var startedAt: Date
    var durationMilliseconds: Int
}

struct ActionExecutionReport {
    let workflowID: UUID
    let status: ActionExecutionStatus
    let logs: [ActionExecutionLog]
    let variables: [String: ActionValue]
}

enum ActionExecutionError: LocalizedError {
    case unknownAction(String)
    case unknownVariable(String)
    case missingParameter(String)
    case invalidCondition(String)
    case invalidNumber(String)

    var errorDescription: String? {
        switch self {
        case .unknownAction(let type):
            return "未登録のアクションです: \(type)"
        case .unknownVariable(let name):
            return "変数「\(name)」が見つかりません"
        case .missingParameter(let name):
            return "必要な設定がありません: \(name)"
        case .invalidCondition(let message):
            return "条件を判定できません: \(message)"
        case .invalidNumber(let value):
            return "数値に変換できません: \(value)"
        }
    }
}

@MainActor
final class ActionExecutionContext {
    private(set) var variables: [String: ActionValue]

    init(initialVariables: [String: ActionValue] = [:]) {
        variables = initialVariables
    }

    func set(_ value: ActionValue, for name: String) {
        variables[name] = value
    }

    func value(for name: String) -> ActionValue? {
        variables[name]
    }
}

@MainActor
final class ActionEngine {
    typealias Handler = @MainActor (
        _ action: ActionDefinition,
        _ context: ActionExecutionContext
    ) async throws -> ActionValue?

    private var handlers: [String: Handler] = [:]
    private let store: ActionStore

    init(store: ActionStore) {
        self.store = store
        registerCoreHandlers()
    }

    func register(type: String, handler: @escaping Handler) {
        handlers[type] = handler
    }

    func run(
        _ workflow: ActionWorkflow,
        initialVariables: [String: ActionValue] = [:]
    ) async -> ActionExecutionReport {
        let context = ActionExecutionContext(initialVariables: initialVariables)
        var runLogs: [ActionExecutionLog] = []
        var hadFailure = false

        for action in workflow.actions {
            guard action.isEnabled else { continue }

            let start = Date()
            do {
                guard let handler = handlers[action.type] else {
                    throw ActionExecutionError.unknownAction(action.type)
                }

                let resolved = try action.resolvingParameters(using: context.variables)
                let result = try await handler(resolved, context)

                if let result, let output = action.outputVariable, !output.isEmpty {
                    context.set(result, for: output)
                }

                let log = makeLog(
                    workflow: workflow,
                    action: action,
                    status: .success,
                    message: "完了",
                    startedAt: start
                )
                runLogs.append(log)
                store.appendLog(log)
            } catch {
                hadFailure = true
                let log = makeLog(
                    workflow: workflow,
                    action: action,
                    status: .failure,
                    message: error.localizedDescription,
                    startedAt: start
                )
                runLogs.append(log)
                store.appendLog(log)

                if action.failurePolicy == .stop {
                    break
                }
            }
        }

        let status: ActionExecutionStatus = hadFailure ? .completedWithErrors : .success
        return ActionExecutionReport(
            workflowID: workflow.id,
            status: status,
            logs: runLogs,
            variables: context.variables
        )
    }

    private func makeLog(
        workflow: ActionWorkflow,
        action: ActionDefinition,
        status: ActionExecutionStatus,
        message: String,
        startedAt: Date
    ) -> ActionExecutionLog {
        ActionExecutionLog(
            workflowID: workflow.id,
            actionID: action.id,
            workflowTitle: workflow.title,
            actionTitle: action.title,
            status: status,
            message: message,
            startedAt: startedAt,
            durationMilliseconds: max(0, Int(Date().timeIntervalSince(startedAt) * 1000))
        )
    }

    private func registerCoreHandlers() {
        register(type: "core.setVariable") { action, context in
            guard case .string(let name)? = action.parameters["name"],
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let value = action.parameters["value"] else {
                throw ActionExecutionError.missingParameter("変数名 / 保存する値")
            }
            context.set(value, for: name)
            return value
        }

        register(type: "core.condition") { action, context in
            guard let left = action.parameters["left"],
                  case .string(let operation)? = action.parameters["operator"],
                  let resultName = action.parameters["resultVariable"],
                  case .string(let outputName) = resultName else {
                throw ActionExecutionError.missingParameter("比較条件 / 判定結果の保存先")
            }

            let right = action.parameters["right"] ?? .null
            let result = try ActionConditionEvaluator.evaluate(
                left: left,
                operation: operation,
                right: right
            )
            let value = ActionValue.bool(result)
            context.set(value, for: outputName)
            return value
        }
    }
}

private extension ActionDefinition {
    func resolvingParameters(using variables: [String: ActionValue]) throws -> ActionDefinition {
        var copy = self
        copy.parameters = try parameters.mapValues {
            try $0.resolvingVariables(variables)
        }
        return copy
    }
}

enum ActionConditionEvaluator {
    static func evaluate(
        left: ActionValue,
        operation: String,
        right: ActionValue
    ) throws -> Bool {
        switch operation {
        case "equal":
            return left == right
        case "notEqual":
            return left != right
        case "contains":
            return left.displayString.localizedCaseInsensitiveContains(right.displayString)
        case "greaterThan":
            guard let lhs = numericValue(left), let rhs = numericValue(right) else {
                throw ActionExecutionError.invalidCondition("数値同士を比較してください")
            }
            return lhs > rhs
        case "lessThan":
            guard let lhs = numericValue(left), let rhs = numericValue(right) else {
                throw ActionExecutionError.invalidCondition("数値同士を比較してください")
            }
            return lhs < rhs
        case "isEmpty":
            return left.displayString.isEmpty
        default:
            throw ActionExecutionError.invalidCondition("未対応の演算子: \(operation)")
        }
    }

    private static func numericValue(_ value: ActionValue) -> Double? {
        switch value {
        case .number(let number): return number
        case .string(let string): return Double(string)
        default: return nil
        }
    }
}
