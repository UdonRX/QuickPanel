import Foundation

// MARK: - Action categories

/// Categories are deliberately stable IDs. Display names can be changed without
/// changing saved workflows.
enum ActionCategory: String, CaseIterable, Codable, Identifiable {
    case appScreen = "appScreen"
    case text = "text"
    case web = "web"
    case workflow = "workflow"
    case information = "information"
    case system = "system"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appScreen: return "アプリ・画面操作"
        case .text: return "文字列操作"
        case .web: return "Web通信"
        case .workflow: return "処理の組み立て"
        case .information: return "情報取得・通知"
        case .system: return "システム設定"
        }
    }

    var symbol: String {
        switch self {
        case .appScreen: return "square.grid.2x2"
        case .text: return "text.alignleft"
        case .web: return "globe"
        case .workflow: return "arrow.triangle.branch"
        case .information: return "bell.badge"
        case .system: return "slider.horizontal.3"
        }
    }
}

// MARK: - JSON-compatible values

/// A small JSON value type used for action parameters and runtime variables.
indirect enum ActionValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([ActionValue])
    case object([String: ActionValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([ActionValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: ActionValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported action value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var displayString: String {
        switch self {
        case .string(let value): return value
        case .number(let value):
            return value.rounded() == value
                ? String(Int(value))
                : String(value)
        case .bool(let value): return value ? "true" : "false"
        case .array, .object:
            guard let data = try? JSONEncoder().encode(self),
                  let string = String(data: data, encoding: .utf8) else {
                return ""
            }
            return string
        case .null: return ""
        }
    }

    /// Replaces ${variableName} placeholders recursively.
    func resolvingVariables(_ variables: [String: ActionValue]) throws -> ActionValue {
        switch self {
        case .string(let original):
            var result = original
            while let start = result.range(of: "${"),
                  let end = result[start.upperBound...].firstIndex(of: "}") {
                let name = String(result[start.upperBound..<end])
                guard let value = variables[name] else {
                    throw ActionExecutionError.unknownVariable(name)
                }
                result.replaceSubrange(start.lowerBound...end, with: value.displayString)
            }
            return .string(result)
        case .array(let values):
            return .array(try values.map { try $0.resolvingVariables(variables) })
        case .object(let values):
            return .object(try values.mapValues { try $0.resolvingVariables(variables) })
        default:
            return self
        }
    }
}

// MARK: - Workflow models

enum ActionFailurePolicy: String, Codable, CaseIterable, Identifiable {
    case stop
    case continueRunning

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stop: return "失敗したら中止"
        case .continueRunning: return "失敗しても続行"
        }
    }
}

struct ActionDefinition: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    /// Stable identifier such as "core.setVariable" or "text.copy".
    var type: String
    var category: ActionCategory
    var title: String
    var parameters: [String: ActionValue] = [:]
    var outputVariable: String?
    var failurePolicy: ActionFailurePolicy = .stop
    var isEnabled: Bool = true

    init(
        id: UUID = UUID(),
        type: String,
        category: ActionCategory,
        title: String,
        parameters: [String: ActionValue] = [:],
        outputVariable: String? = nil,
        failurePolicy: ActionFailurePolicy = .stop,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.type = type
        self.category = category
        self.title = title
        self.parameters = parameters
        self.outputVariable = outputVariable
        self.failurePolicy = failurePolicy
        self.isEnabled = isEnabled
    }
}

struct ActionWorkflow: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var icon: String = "bolt.fill"
    var colorIndex: Int = 0
    var actions: [ActionDefinition] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    mutating func touch() {
        updatedAt = Date()
    }
}

// MARK: - Builder metadata

/// These field types let the next-stage editor show pickers, switches and
/// number controls instead of asking users to type technical identifiers.
enum ActionFieldKind: String, Codable {
    case shortText
    case multilineText
    case number
    case toggle
    case url
    case appPicker
    case systemSettingPicker
    case duration
    case variableName
    case choice
}

struct ActionFieldOption: Codable, Equatable, Identifiable {
    var id: String { value }
    let title: String
    let value: String
}

struct ActionFieldSchema: Codable, Equatable, Identifiable {
    var id: String { key }
    let key: String
    let title: String
    let kind: ActionFieldKind
    var isRequired: Bool = false
    var placeholder: String? = nil
    var options: [ActionFieldOption] = []
}

struct ActionDescriptor: Codable, Equatable, Identifiable {
    var id: String { type }
    let type: String
    let category: ActionCategory
    let title: String
    let description: String
    let fields: [ActionFieldSchema]
}

/// Catalog metadata is the single source of truth for category-first creation.
/// New action types can be added here without changing the workflow data format.
enum ActionCatalog {
    static let categories = ActionCategory.allCases

    static let coreActions: [ActionDescriptor] = [
        ActionDescriptor(
            type: "core.setVariable",
            category: .workflow,
            title: "変数に値を保存",
            description: "後続のアクションで使う値を保存する",
            fields: [
                ActionFieldSchema(key: "name", title: "変数名", kind: .variableName, isRequired: true, placeholder: "result"),
                ActionFieldSchema(key: "value", title: "保存する値", kind: .multilineText, isRequired: true)
            ]
        ),
        ActionDescriptor(
            type: "core.condition",
            category: .workflow,
            title: "条件を判定",
            description: "2つの値を比較して true / false を返す",
            fields: [
                ActionFieldSchema(key: "left", title: "比較する値", kind: .shortText, isRequired: true, placeholder: "${variableName}"),
                ActionFieldSchema(
                    key: "operator",
                    title: "条件",
                    kind: .choice,
                    isRequired: true,
                    options: [
                        ActionFieldOption(title: "等しい", value: "equal"),
                        ActionFieldOption(title: "等しくない", value: "notEqual"),
                        ActionFieldOption(title: "含む", value: "contains"),
                        ActionFieldOption(title: "より大きい", value: "greaterThan"),
                        ActionFieldOption(title: "より小さい", value: "lessThan"),
                        ActionFieldOption(title: "空である", value: "isEmpty")
                    ]
                ),
                ActionFieldSchema(key: "right", title: "比較対象", kind: .shortText, placeholder: "${anotherVariable}"),
                ActionFieldSchema(key: "resultVariable", title: "判定結果の保存先", kind: .variableName, isRequired: true)
            ]
        )
    ]

    static func actions(in category: ActionCategory) -> [ActionDescriptor] {
        coreActions.filter { $0.category == category }
    }

    static func descriptor(for type: String) -> ActionDescriptor? {
        coreActions.first { $0.type == type }
    }
}
