import Foundation
import UIKit
import UserNotifications
import AVFoundation

enum ActionExecutionStatus:String,Codable { case success,failure,skipped,completedWithErrors }
struct ActionExecutionLog:Identifiable,Codable,Equatable {
    var id:UUID=UUID()
    var workflowID:UUID
    var actionID:UUID?
    var workflowTitle:String
    var actionTitle:String
    var status:ActionExecutionStatus
    var message:String
    var startedAt:Date
    var durationMilliseconds:Int
}
struct ActionExecutionReport {
    let workflowID:UUID
    let status:ActionExecutionStatus
    let logs:[ActionExecutionLog]
    let variables:[String:ActionValue]
}
enum ActionExecutionError:LocalizedError {
    case unknownAction(String),unknownVariable(String),missingParameter(String),invalidCondition(String),invalidNumber(String),invalidURL(String),operationFailed(String)
    var errorDescription:String? {
        switch self {
        case .unknownAction(let v):return "未登録のアクション: \(v)"
        case .unknownVariable(let v):return "変数「\(v)」が見つかりません"
        case .missingParameter(let v):return "必要な設定がありません: \(v)"
        case .invalidCondition(let v):return "条件を判定できません: \(v)"
        case .invalidNumber(let v):return "数値に変換できません: \(v)"
        case .invalidURL(let v):return "URLが正しくありません: \(v)"
        case .operationFailed(let v):return v
        }
    }
}
@MainActor final class ActionExecutionContext {
    private(set) var variables:[String:ActionValue]
    init(initialVariables:[String:ActionValue]=[:]){variables=initialVariables}
    func set(_ value:ActionValue,for name:String){variables[name]=value}
    func value(for name:String)->ActionValue?{variables[name]}
}
@MainActor final class ActionEngine {
    typealias Handler = @MainActor (ActionDefinition,ActionExecutionContext) async throws -> ActionValue?
    private var handlers:[String:Handler]=[:]
    private let store:ActionStore
    init(store:ActionStore){self.store=store;registerBuiltIns()}
    func register(type:String,handler:@escaping Handler){handlers[type]=handler}
    func run(_ workflow:ActionWorkflow,initialVariables:[String:ActionValue]=[:]) async->ActionExecutionReport {
        let context=ActionExecutionContext(initialVariables:initialVariables)
        var logs:[ActionExecutionLog]=[]
        var failed=false
        for action in workflow.actions where action.isEnabled {
            let start=Date()
            do {
                guard let handler=handlers[action.type] else{throw ActionExecutionError.unknownAction(action.type)}
                let resolved=try action.resolvingParameters(using:context.variables)
                let result=try await handler(resolved,context)
                if let result,let output=action.outputVariable,!output.isEmpty{context.set(result,for:output)}
                let log=makeLog(workflow,action,.success,"完了",start)
                logs.append(log);store.appendLog(log)
            } catch {
                failed=true
                let log=makeLog(workflow,action,.failure,error.localizedDescription,start)
                logs.append(log);store.appendLog(log)
                if action.failurePolicy == .stop{break}
            }
        }
        return ActionExecutionReport(workflowID:workflow.id,status:failed ? .completedWithErrors:.success,logs:logs,variables:context.variables)
    }
    private func makeLog(_ w:ActionWorkflow,_ a:ActionDefinition,_ s:ActionExecutionStatus,_ m:String,_ start:Date)->ActionExecutionLog {
        ActionExecutionLog(workflowID:w.id,actionID:a.id,workflowTitle:w.title,actionTitle:a.title,status:s,message:m,startedAt:start,durationMilliseconds:max(0,Int(Date().timeIntervalSince(start)*1000)))
    }
    private func string(_ action:ActionDefinition,_ key:String,required:Bool=true)throws->String {
        guard let value=action.parameters[key] else{if required{throw ActionExecutionError.missingParameter(key)};return ""}
        let result=value.displayString
        if required && result.isEmpty{throw ActionExecutionError.missingParameter(key)}
        return result
    }
    private func registerBuiltIns() {
        register(type:"workflow.setVariable"){[weak self] a,c in
            guard let self else{return nil}
            let name=try self.string(a,"name")
            guard let value=a.parameters["value"] else{throw ActionExecutionError.missingParameter("保存する値")}
            c.set(value,for:name);return value
        }
        register(type:"workflow.condition"){[weak self] a,c in
            guard let self else{return nil}
            let left=try self.string(a,"left"), op=try self.string(a,"operator")
            let right=try self.string(a,"right",required:false), output=try self.string(a,"resultVariable")
            let result=try ActionConditionEvaluator.evaluate(left:.string(left),operation:op,right:.string(right))
            let value=ActionValue.bool(result);c.set(value,for:output);return value
        }
        register(type:"workflow.wait"){[weak self] a,_ in
            guard let self else{return nil}
            let raw=try self.string(a,"seconds")
            guard let seconds=Double(raw),seconds>=0,seconds<=300 else{throw ActionExecutionError.invalidNumber(raw)}
            try await Task.sleep(nanoseconds:UInt64(seconds*1_000_000_000))
            return .number(seconds)
        }
        register(type:"app.openURL"){[weak self] a,_ in
            guard let self else{return nil}
            let custom=try self.string(a,"customURL",required:false)
            let raw=custom.isEmpty ? try self.string(a,"destination"):custom
            guard let url=URL(string:raw),let scheme=url.scheme,!scheme.isEmpty else{throw ActionExecutionError.invalidURL(raw)}
            let ok=await UIApplication.shared.open(url)
            if !ok{throw ActionExecutionError.operationFailed("アプリまたはURLを開けませんでした")}
            return .string(url.absoluteString)
        }
        register(type:"app.openSettings"){[weak self] a,_ in
            guard let self else{return nil}
            let setting=try self.string(a,"setting")
            let ok=await UIApplication.shared.open(Self.settingsURL(setting))
            if !ok{throw ActionExecutionError.operationFailed("設定画面を開けませんでした")}
            return .string(setting)
        }
        register(type:"text.copy"){[weak self] a,_ in
            guard let self else{return nil}
            let text=try self.string(a,"text");UIPasteboard.general.string=text;return .string(text)
        }
        register(type:"text.replace"){[weak self] a,_ in
            guard let self else{return nil}
            let text=try self.string(a,"text"),find=try self.string(a,"find")
            return .string(text.replacingOccurrences(of:find,with:try self.string(a,"replacement",required:false)))
        }
        register(type:"text.join"){[weak self] a,_ in
            guard let self else{return nil}
            let first=try self.string(a,"first"),second=try self.string(a,"second")
            return .string(first+(try self.string(a,"separator",required:false))+second)
        }
        register(type:"web.request"){[weak self] a,_ in
            guard let self else{return nil}
            let method=try self.string(a,"method"),raw=try self.string(a,"url")
            guard let url=URL(string:raw),["http","https"].contains(url.scheme?.lowercased() ?? "") else{throw ActionExecutionError.invalidURL(raw)}
            var request=URLRequest(url:url);request.httpMethod=method;request.timeoutInterval=30
            if method=="POST" {
                let body=try self.string(a,"body",required:false)
                if !body.isEmpty{request.httpBody=Data(body.utf8);request.setValue("application/json",forHTTPHeaderField:"Content-Type")}
            }
            let (data,response)=try await URLSession.shared.data(for:request)
            if let http=response as? HTTPURLResponse,!(200...299).contains(http.statusCode){throw ActionExecutionError.operationFailed("Web通信エラー：HTTP \(http.statusCode)")}
            return .string(String(data:data,encoding:.utf8) ?? data.base64EncodedString())
        }
        register(type:"information.currentDate"){[weak self] a,c in
            guard let self else{return nil}
            let format=try self.string(a,"format"),output=try self.string(a,"output")
            let formatter=DateFormatter();formatter.locale=Locale(identifier:"ja_JP");formatter.timeZone = .current
            formatter.dateFormat=format=="iso8601" ? nil:format
            let value=format=="iso8601" ? ISO8601DateFormatter().string(from:Date()):formatter.string(from:Date())
            c.set(.string(value),for:output);return .string(value)
        }
        register(type:"information.battery"){[weak self] a,c in
            guard let self else{return nil}
            let output=try self.string(a,"output")
            UIDevice.current.isBatteryMonitoringEnabled=true
            let level=UIDevice.current.batteryLevel
            guard level>=0 else{throw ActionExecutionError.operationFailed("バッテリー残量を取得できません")}
            let value=ActionValue.number(Double(Int((level*100).rounded())))
            c.set(value,for:output);return value
        }
        register(type:"information.notify"){[weak self] a,_ in
            guard let self else{return nil}
            let title=try self.string(a,"title"),message=try self.string(a,"message")
            let center=UNUserNotificationCenter.current()
            let settings=await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined{_ = try await center.requestAuthorization(options:[.alert,.sound,.badge])}
            let content=UNMutableNotificationContent();content.title=title;content.body=message;content.sound = .default
            try await center.add(UNNotificationRequest(identifier:UUID().uuidString,content:content,trigger:nil))
            return .string(message)
        }
        register(type:"system.openSettings"){[weak self] a,_ in
            guard let self else{return nil}
            let setting=try self.string(a,"setting")
            let ok=await UIApplication.shared.open(Self.settingsURL(setting))
            if !ok{throw ActionExecutionError.operationFailed("設定画面を開けませんでした")}
            return .string(setting)
        }
        register(type:"system.torch"){[weak self] a,_ in
            guard let self else{return nil}
            let enabled=a.parameters["enabled"] == .bool(true)
            guard let device=AVCaptureDevice.default(for:.video),device.hasTorch else{throw ActionExecutionError.operationFailed("この端末ではライトを使えません")}
            try device.lockForConfiguration()
            defer{device.unlockForConfiguration()}
            if enabled{try device.setTorchModeOn(level:AVCaptureDevice.maxAvailableTorchLevel)}
            else{device.torchMode = .off}
            return .bool(enabled)
        }
        register(type:"system.shortcutFallback"){[weak self] a,_ in
            guard let self else{return nil}
            let name=try self.string(a,"shortcutName")
            var c=URLComponents();c.scheme="shortcuts";c.host="run-shortcut";c.queryItems=[URLQueryItem(name:"name",value:name)]
            guard let url=c.url else{throw ActionExecutionError.invalidURL(name)}
            let ok=await UIApplication.shared.open(url)
            if !ok{throw ActionExecutionError.operationFailed("ショートカットを起動できませんでした")}
            return .string(name)
        }
    }
    // Wi-Fi/Bluetooth toggles are not exposed as ordinary-app APIs. This opens the Settings pane where iOS permits it; actual toggling uses the named Shortcuts fallback action.
    private static func settingsURL(_ setting:String)->URL {
        switch setting {
        case "app":return URL(string:UIApplication.openSettingsURLString)!
        // These deep links are not a guaranteed public API; if iOS rejects them,
        // use the dedicated Shortcuts fallback action in the workflow editor.
        case "wifi":return URL(string:"App-Prefs:root=WIFI")!
        case "bluetooth":return URL(string:"App-Prefs:root=Bluetooth")!
        case "notifications":return URL(string:"App-Prefs:root=NOTIFICATIONS_ID")!
        case "general":return URL(string:"App-Prefs:root=General")!
        default:return URL(string:UIApplication.openSettingsURLString)!
        }
    }
}
private extension ActionDefinition {
    func resolvingParameters(using variables:[String:ActionValue])throws->ActionDefinition {
        var copy=self
        copy.parameters=try parameters.mapValues{try $0.resolvingVariables(variables)}
        return copy
    }
}
enum ActionConditionEvaluator {
    static func evaluate(left:ActionValue,operation:String,right:ActionValue)throws->Bool {
        switch operation {
        case "equal":return left==right
        case "notEqual":return left != right
        case "contains":return left.displayString.localizedCaseInsensitiveContains(right.displayString)
        case "greaterThan","lessThan":
            guard let l=Double(left.displayString),let r=Double(right.displayString) else{throw ActionExecutionError.invalidCondition("数値同士を比較してください")}
            return operation=="greaterThan" ? l>r:l<r
        case "isEmpty":return left.displayString.isEmpty
        default:throw ActionExecutionError.invalidCondition("未対応の条件: \(operation)")
        }
    }
}
