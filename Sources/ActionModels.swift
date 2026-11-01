import Foundation

enum ActionCategory: String, CaseIterable, Codable, Identifiable {
    case appScreen, text, web, workflow, information, system
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
indirect enum ActionValue: Codable, Equatable {
    case string(String), number(Double), bool(Bool), array([ActionValue]), object([String:ActionValue]), null
    init(from decoder:Decoder)throws {
        let c=try decoder.singleValueContainer()
        if c.decodeNil(){self = .null}
        else if let v=try? c.decode(Bool.self){self = .bool(v)}
        else if let v=try? c.decode(Double.self){self = .number(v)}
        else if let v=try? c.decode(String.self){self = .string(v)}
        else if let v=try? c.decode([ActionValue].self){self = .array(v)}
        else if let v=try? c.decode([String:ActionValue].self){self = .object(v)}
        else{throw DecodingError.dataCorruptedError(in:c,debugDescription:"Unsupported action value")}
    }
    func encode(to encoder:Encoder)throws {
        var c=encoder.singleValueContainer()
        switch self {
        case .string(let v):try c.encode(v)
        case .number(let v):try c.encode(v)
        case .bool(let v):try c.encode(v)
        case .array(let v):try c.encode(v)
        case .object(let v):try c.encode(v)
        case .null:try c.encodeNil()
        }
    }
    var displayString:String {
        switch self {
        case .string(let v):return v
        case .number(let v):return v.rounded()==v ? String(Int(v)):String(v)
        case .bool(let v):return v ? "true":"false"
        case .array,.object:guard let d=try? JSONEncoder().encode(self) else{return ""};return String(data:d,encoding:.utf8) ?? ""
        case .null:return ""
        }
    }
    func resolvingVariables(_ variables:[String:ActionValue])throws->ActionValue {
        switch self {
        case .string(let original):
            var result=original
            while let start=result.range(of:"${"),let end=result[start.upperBound...].firstIndex(of:"}") {
                let name=String(result[start.upperBound..<end])
                guard let value=variables[name] else{throw ActionExecutionError.unknownVariable(name)}
                result.replaceSubrange(start.lowerBound...end,with:value.displayString)
            }
            return .string(result)
        case .array(let values):return .array(try values.map{try $0.resolvingVariables(variables)})
        case .object(let values):return .object(try values.mapValues{try $0.resolvingVariables(variables)})
        default:return self
        }
    }
}
enum ActionFailurePolicy:String,Codable,CaseIterable,Identifiable {
    case stop,continueRunning
    var id:String{rawValue}
    var title:String{self == .stop ? "失敗したら中止":"失敗しても続行"}
}
struct ActionDefinition:Identifiable,Codable,Equatable {
    var id:UUID=UUID()
    var type:String
    var category:ActionCategory
    var title:String
    var parameters:[String:ActionValue]=[:]
    var outputVariable:String?
    var failurePolicy:ActionFailurePolicy = .stop
    var isEnabled:Bool = true
}
struct ActionWorkflow:Identifiable,Codable,Equatable {
    var id:UUID=UUID()
    var title:String
    var icon:String="bolt.fill"
    var colorIndex:Int=0
    var actions:[ActionDefinition]=[]
    var createdAt:Date=Date()
    var updatedAt:Date=Date()
    mutating func touch(){updatedAt=Date()}
}
enum ActionFieldKind:String,Codable { case shortText,multilineText,number,toggle,url,appPicker,systemSettingPicker,duration,variableName,choice }
struct ActionFieldOption:Codable,Equatable,Identifiable { var id:String{value};let title:String;let value:String }
struct ActionFieldSchema:Codable,Equatable,Identifiable {
    var id:String{key}
    let key:String
    let title:String
    let kind:ActionFieldKind
    var isRequired:Bool=false
    var placeholder:String?=nil
    var options:[ActionFieldOption]=[]
}
struct ActionDescriptor:Codable,Equatable,Identifiable {
    var id:String{type}
    let type:String
    let category:ActionCategory
    let title:String
    let description:String
    let fields:[ActionFieldSchema]
}
enum ActionCatalog {
    static let categories=ActionCategory.allCases
    private static func f(_ key:String,_ title:String,_ kind:ActionFieldKind,_ required:Bool=false,_ placeholder:String?=nil,_ options:[ActionFieldOption]=[])->ActionFieldSchema {
        ActionFieldSchema(key:key,title:title,kind:kind,isRequired:required,placeholder:placeholder,options:options)
    }
    private static func o(_ title:String,_ value:String)->ActionFieldOption{.init(title:title,value:value)}
    static let all:[ActionDescriptor] = [
        .init(type:"app.openURL",category:.appScreen,title:"アプリ・URLを開く",description:"アプリのURLまたはWebアドレスを開く",fields:[
            f("destination","開く先",.appPicker,true,nil,[o("Safari（Web）","https://www.apple.com"),o("マップ","maps://"),o("設定","app-settings:"),o("電話","tel:"),o("メール","mailto:"),o("メッセージ","sms:")]),
            f("customURL","またはURLを指定",.url,false,"https:// または myapp://")
        ]),
        .init(type:"app.openSettings",category:.appScreen,title:"設定画面を開く",description:"iOSの設定画面を表示",fields:[
            f("setting","設定画面",.choice,true,nil,[o("QuickPanelの設定","app"),o("Wi-Fi設定","wifi"),o("Bluetooth設定","bluetooth"),o("通知設定","notifications"),o("一般設定","general")])
        ]),
        .init(type:"text.copy",category:.text,title:"テキストをコピー",description:"文章をクリップボードにコピー",fields:[f("text","コピーする文章",.multilineText,true)]),
        .init(type:"text.replace",category:.text,title:"文字列を置換",description:"文章中の文字を置き換える",fields:[f("text","元の文章",.multilineText,true),f("find","検索する文字",.shortText,true),f("replacement","置き換える文字",.shortText)]),
        .init(type:"text.join",category:.text,title:"文字列を結合",description:"2つの文字列を区切り文字で結合",fields:[f("first","1つ目の文字",.shortText,true),f("second","2つ目の文字",.shortText,true),f("separator","区切り文字",.shortText)]),
        .init(type:"web.request",category:.web,title:"Web APIにアクセス",description:"GET / POSTでデータを取得・送信",fields:[f("method","通信方法",.choice,true,nil,[o("GET","GET"),o("POST","POST")]),f("url","URL",.url,true,"https://example.com/api"),f("body","送信内容（POST時）",.multilineText)]),
        .init(type:"workflow.setVariable",category:.workflow,title:"変数に値を保存",description:"後続の処理で使う値を保存",fields:[f("name","変数名",.variableName,true,"result"),f("value","保存する値",.multilineText,true)]),
        .init(type:"workflow.wait",category:.workflow,title:"指定時間待つ",description:"次の処理まで待機",fields:[f("seconds","待機する秒数",.number,true,"1")]),
        .init(type:"workflow.condition",category:.workflow,title:"条件を判定",description:"2つの値を比較して結果を変数に保存",fields:[
            f("left","比較する値",.shortText,true,"${variableName}"),
            f("operator","条件",.choice,true,nil,[o("等しい","equal"),o("等しくない","notEqual"),o("含む","contains"),o("より大きい","greaterThan"),o("より小さい","lessThan"),o("空である","isEmpty")]),
            f("right","比較対象",.shortText,false,"${anotherVariable}"),f("resultVariable","判定結果の保存先",.variableName,true)
        ]),
        .init(type:"information.currentDate",category:.information,title:"現在日時を取得",description:"現在日時を変数に保存",fields:[f("format","日時形式",.choice,true,nil,[o("2026-11-01 19:30","yyyy-MM-dd HH:mm"),o("2026/11/01","yyyy/MM/dd"),o("19:30","HH:mm"),o("ISO 8601","iso8601")]),f("output","保存先の変数名",.variableName,true)]),
        .init(type:"information.battery",category:.information,title:"バッテリー残量を取得",description:"iPhoneのバッテリー残量（%）を取得",fields:[f("output","保存先の変数名",.variableName,true)]),
        .init(type:"information.notify",category:.information,title:"通知を表示",description:"QuickPanelからiPhoneに通知",fields:[f("title","通知タイトル",.shortText,true),f("message","通知内容",.multilineText,true)]),
        .init(type:"system.openSettings",category:.system,title:"設定画面を開く",description:"iOS設定画面を開く",fields:[f("setting","設定画面",.systemSettingPicker,true,nil,[o("QuickPanelの設定","app"),o("Wi-Fi","wifi"),o("Bluetooth","bluetooth"),o("通知","notifications"),o("一般","general")])]),
        .init(type:"system.torch",category:.system,title:"ライトをON/OFF",description:"iPhoneのカメラライトを直接操作",fields:[f("enabled","ライトを点灯する",.toggle)]),
        .init(type:"system.shortcutFallback",category:.system,title:"ショートカットで設定操作",description:"アプリ単体で操作できない設定をショートカットに任せる",fields:[
            f("operation","設定操作",.choice,true,nil,[o("Wi-Fiをオン","wifiOn"),o("Wi-Fiをオフ","wifiOff"),o("Bluetoothをオン","bluetoothOn"),o("Bluetoothをオフ","bluetoothOff"),o("その他","other")]),
            f("shortcutName","実行するショートカット名",.shortText,true,"Wi-Fiをオン")
        ])
    ]
    static func actions(in category:ActionCategory)->[ActionDescriptor]{all.filter{$0.category==category}}
    static func descriptor(for type:String)->ActionDescriptor?{all.first{$0.type==type}}
}
