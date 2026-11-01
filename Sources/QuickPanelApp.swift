import SwiftUI
import UIKit
import Combine
import AVFoundation

enum ButtonKind:String,CaseIterable,Codable,Identifiable {
    case app="アプリ",shortcut="ショートカット",setting="設定・操作",workflow="アクション"
    var id:String{rawValue}
}
enum AppLaunchMethod:String,CaseIterable,Codable,Identifiable {
    case bundleIdentifier="Bundle IDから起動"
    case urlScheme="URLスキームで起動"
    case universalLink="URL / Universal Linkで起動"
    case shortcut="ショートカットで起動"
    var id:String{rawValue}
}
enum TileSize:String,CaseIterable,Codable,Identifiable {
    case small="1×1",wide="2×1",large="2×2"
    var id:String{rawValue}
    var columns:Int{self == .small ? 1:2}
    var rows:Int{self == .large ? 2:1}
}
struct PanelButton:Identifiable,Codable {
    var id:UUID=UUID()
    var title:String
    var kind:ButtonKind
    var target:String
    var icon:String
    var colorIndex:Int
    var size:TileSize = .small
    var column:Int=0
    var row:Int=0
    var launchMethod:AppLaunchMethod?=nil
    var bundleIdentifier:String?=nil
    var shortcutName:String?=nil
}
struct AppPreset:Identifiable {
    let id:String;let name:String;let url:String;let icon:String
}
@MainActor final class PanelStore:ObservableObject {
    @Published var buttons:[PanelButton]=[] { didSet{save()} }
    private let key="QuickPanel.Buttons.v2"
    init(){load()}
    func load(){
        guard let data=UserDefaults.standard.data(forKey:key),let decoded=try? JSONDecoder().decode([PanelButton].self,from:data) else{return}
        buttons=decoded
    }
    func save(){guard let data=try? JSONEncoder().encode(buttons) else{return};UserDefaults.standard.set(data,forKey:key)}
    func add(_ button:PanelButton){
        var value=button;value.id=UUID()
        let p=firstFree(column:value.column,row:value.row,size:value.size,excluding:nil)
        value.column=p.0;value.row=p.1;buttons.append(value)
    }
    func update(_ button:PanelButton){
        guard let i=buttons.firstIndex(where:{$0.id==button.id}) else{return}
        buttons[i]=button;normalize()
    }
    func duplicate(_ button:PanelButton){
        var copy=button;copy.id=UUID();copy.title += " コピー"
        let p=firstFree(column:button.column+button.size.columns,row:button.row,size:button.size,excluding:nil)
        copy.column=p.0;copy.row=p.1;buttons.append(copy)
    }
    func delete(_ button:PanelButton){buttons.removeAll{$0.id==button.id}}
    func move(_ button:PanelButton,column:Int,row:Int){
        guard let i=buttons.firstIndex(where:{$0.id==button.id}) else{return}
        let p=firstFree(column:column,row:row,size:button.size,excluding:button.id)
        buttons[i].column=p.0;buttons[i].row=p.1
    }
    private func firstFree(column:Int,row:Int,size:TileSize,excluding:UUID?)->(Int,Int){
        let startColumn=min(max(0,column),4-size.columns),startRow=max(0,row)
        for r in startRow...(startRow+500){
            for c in 0...(4-size.columns){
                let actual=r==startRow ? max(startColumn,c):c
                if actual<=4-size.columns && isFree(column:actual,row:r,size:size,excluding:excluding){return(actual,r)}
            }
        }
        return(0,startRow+501)
    }
    private func isFree(column:Int,row:Int,size:TileSize,excluding:UUID?)->Bool{
        for item in buttons where item.id != excluding {
            let x=column<item.column+item.size.columns && column+size.columns>item.column
            let y=row<item.row+item.size.rows && row+size.rows>item.row
            if x && y{return false}
        }
        return true
    }
    private func normalize(){
        let old=buttons;buttons=[]
        for item in old{
            var copy=item
            let p=firstFree(column:copy.column,row:copy.row,size:copy.size,excluding:nil)
            copy.column=p.0;copy.row=p.1;buttons.append(copy)
        }
    }
}
@main struct QuickPanelApp:App {
    var body:some Scene{WindowGroup{MainView().preferredColorScheme(.dark)}}
}

struct MainView:View {
    @StateObject private var panelStore=PanelStore()
    @StateObject private var actionStore=ActionStore()
    @State private var showAddMenu=false
    @State private var showAppEditor=false
    @State private var editingButton:PanelButton?
    @State private var editingWorkflow:ActionWorkflow?
    @State private var isEditing=false
    @State private var showResult=false
    @State private var resultText=""
    @State private var shouldOpenCamera=false
    private let spacing:CGFloat=10
    private let sidePadding:CGFloat=16
    var body:some View{
        NavigationStack{
            GeometryReader{geometry in
                let unit=(geometry.size.width-sidePadding*2-spacing*3)/4
                let rowHeight=unit+spacing
                ScrollView{
                    ZStack(alignment:.topLeading){
                        Color.clear.frame(height:max(350,CGFloat(maxRow+1)*rowHeight))
                        ForEach(panelStore.buttons){item in
                            TileView(item:item,editing:isEditing,
                                editAction:{edit(item)},
                                duplicateAction:{panelStore.duplicate(item)},
                                deleteAction:{panelStore.delete(item)},
                                moveAction:{x,y in panelStore.move(item,column:Int(round(x/rowHeight)),row:Int(round(y/rowHeight)))},
                                runAction:{run(item)})
                            .frame(width:CGFloat(item.size.columns)*unit+CGFloat(item.size.columns-1)*spacing,
                                   height:CGFloat(item.size.rows)*unit+CGFloat(item.size.rows-1)*spacing)
                            .position(x:sidePadding+CGFloat(item.column)*rowHeight+(CGFloat(item.size.columns)*unit+CGFloat(item.size.columns-1)*spacing)/2,
                                      y:CGFloat(item.row)*rowHeight+(CGFloat(item.size.rows)*unit+CGFloat(item.size.rows-1)*spacing)/2)
                        }
                    }.padding(.top,12).padding(.bottom,30)
                }
            }
            .background(Color(red:0.055,green:0.065,blue:0.085))
            .navigationTitle("QuickPanel")
            .toolbar{
                ToolbarItem(placement:.topBarLeading){
                    Button{isEditing.toggle()}label:{Image(systemName:"square.grid.2x2").font(.title2).foregroundStyle(isEditing ? .orange:.white)}
                }
                ToolbarItem(placement:.topBarTrailing){
                    Button{showAddMenu=true}label:{Image(systemName:"plus.circle.fill").font(.title2).foregroundStyle(.white)}
                }
            }
            .confirmationDialog("タイルを追加",isPresented:$showAddMenu,titleVisibility:.visible){
                Button("アプリ・URLタイル"){showAppEditor=true}
                Button("アクションタイルを作成"){editingWorkflow=ActionWorkflow(title:"新しいアクション")}
                Button("キャンセル",role:.cancel){}
            }message:{Text("アプリを開くか、複数の処理を組み合わせるアクションを作成する")}
            .sheet(isPresented:$showAppEditor){AppTileEditor{panelStore.add($0)}}
            .sheet(item:$editingButton){button in AppTileEditor(existing:button){panelStore.update($0)}}
            .sheet(item:$editingWorkflow){workflow in
                WorkflowEditorView(existing:workflow){saved in
                    actionStore.saveWorkflow(saved)
                    if let tile=panelStore.buttons.first(where:{$0.kind == .workflow && $0.target==saved.id.uuidString}){
                        var updated=tile;updated.title=saved.title;updated.icon=saved.icon;updated.colorIndex=saved.colorIndex
                        panelStore.update(updated)
                    }else{
                        panelStore.add(PanelButton(title:saved.title,kind:.workflow,target:saved.id.uuidString,icon:saved.icon,colorIndex:saved.colorIndex))
                    }
                }
            }
            .overlay{
                if panelStore.buttons.isEmpty{
                    ContentUnavailableView("タイルがありません",systemImage:"square.grid.2x2",description:Text("右上の＋からアプリまたはアクションを追加してね"))
                }
            }
            .alert("実行結果",isPresented:$showResult){Button("OK",role:.cancel){}}message:{Text(resultText)}
            .onAppear{requestCameraPermissionIfNeeded()}
            .onReceive(NotificationCenter.default.publisher(for:.cameraControlDidActivate)){_ in
                shouldOpenCamera=true
            }
            .fullScreenCover(isPresented:$shouldOpenCamera){
                QuickPanelCameraPicker{shouldOpenCamera=false}
                    .ignoresSafeArea()
            }
        }
    }
    private func requestCameraPermissionIfNeeded(){
        guard AVCaptureDevice.authorizationStatus(for:.video) == .notDetermined else{return}
        AVCaptureDevice.requestAccess(for:.video){_ in}
    }
    private var maxRow:Int{panelStore.buttons.map{$0.row+$0.size.rows}.max() ?? 3}
    private func edit(_ item:PanelButton){
        if item.kind == .workflow,let id=UUID(uuidString:item.target),let workflow=actionStore.workflow(id:id){editingWorkflow=workflow}
        else{editingButton=item}
    }
    private func run(_ item:PanelButton){
        if item.kind == .workflow,let id=UUID(uuidString:item.target),let workflow=actionStore.workflow(id:id){
            Task{
                let report=await ActionEngine(store:actionStore).run(workflow)
                let errors=report.logs.filter{$0.status == .failure}
                resultText=errors.isEmpty ? "「\(workflow.title)」を実行したよ。\n\(report.logs.count)件の処理が完了。":errors.map{"\($0.actionTitle)：\($0.message)"}.joined(separator:"\n")
                showResult=true
            }
        }else{
            let method=item.launchMethod ?? (item.kind == .shortcut || item.kind == .setting ? .shortcut : .urlScheme)
            if method == .shortcut {
                let name=item.shortcutName ?? item.target
                var c=URLComponents();c.scheme="shortcuts";c.host="run-shortcut";c.queryItems=[URLQueryItem(name:"name",value:name)]
                if let url=c.url{UIApplication.shared.open(url)}
            } else {
                let raw:String
                if method == .bundleIdentifier {
                    let identifier=(item.bundleIdentifier ?? item.target).trimmingCharacters(in:.whitespacesAndNewlines)
                    let clean=identifier.hasSuffix("://") ? String(identifier.dropLast(3)):identifier
                    raw=clean+"://"
                } else { raw=item.target }
                guard let url=URL(string:raw),url.scheme != nil else{resultText="起動先URLが正しくありません";showResult=true;return}
                UIApplication.shared.open(url)
            }
        }
    }
}

struct TileView:View {
    let item:PanelButton
    let editing:Bool
    let editAction:()->Void
    let duplicateAction:()->Void
    let deleteAction:()->Void
    let moveAction:(CGFloat,CGFloat)->Void
    let runAction:()->Void
    @State private var dragOffset:CGSize = .zero
    private let colors:[Color]=[
        Color(red:0.14,green:0.23,blue:0.34),Color(red:0.18,green:0.29,blue:0.24),
        Color(red:0.29,green:0.23,blue:0.36),Color(red:0.35,green:0.27,blue:0.18),
        Color(red:0.17,green:0.29,blue:0.34)
    ]
    var body:some View{
        Button{if !editing{runAction()}}label:{
            VStack(alignment:.leading,spacing:10){
                HStack{
                    Image(systemName:item.icon).font(.system(size:27,weight:.medium))
                    Spacer()
                    if editing{
                        Menu{
                            Button("編集",systemImage:"pencil",action:editAction)
                            Button("複製",systemImage:"plus.square.on.square",action:duplicateAction)
                            Divider()
                            Button("削除",systemImage:"trash",role:.destructive,action:deleteAction)
                        }label:{Image(systemName:"ellipsis.circle").font(.title2)}
                    }
                }
                Spacer(minLength:2)
                Text(item.title).font(.system(size:16,weight:.semibold)).lineLimit(2)
                Text(item.kind.rawValue+" · "+item.size.rawValue).font(.system(size:10)).foregroundStyle(.white.opacity(0.65))
            }
            .foregroundStyle(.white).padding(14).frame(maxWidth:.infinity,maxHeight:.infinity)
            .background(colors[abs(item.colorIndex)%colors.count]).clipShape(RoundedRectangle(cornerRadius:20))
            .overlay{if editing{RoundedRectangle(cornerRadius:20).stroke(.white.opacity(0.35),style:StrokeStyle(lineWidth:1,dash:[5]))}}
        }
        .buttonStyle(.plain).offset(dragOffset)
        .gesture(
            LongPressGesture(minimumDuration:0.32)
                .sequenced(before:DragGesture(minimumDistance:0))
                .onChanged{value in
                    guard editing else{return}
                    if case .second(true,let drag?)=value{dragOffset=drag.translation}
                }
                .onEnded{value in
                    if editing,case .second(true,let drag?)=value{
                        moveAction(drag.translation.width,drag.translation.height)
                    }
                    dragOffset = .zero
                }
        )
        .contextMenu{
            Button("編集",systemImage:"pencil",action:editAction)
            Button("複製",systemImage:"plus.square.on.square",action:duplicateAction)
            Button("削除",systemImage:"trash",role:.destructive,action:deleteAction)
        }
    }
}

struct AppTileEditor:View {
    var existing:PanelButton?=nil
    let onSave:(PanelButton)->Void
    @Environment(\.dismiss) private var dismiss
    @State private var title=""
    @State private var launchMethod:AppLaunchMethod = .bundleIdentifier
    @State private var bundleIdentifier=""
    @State private var urlValue=""
    @State private var shortcutName=""
    @State private var icon="app"
    @State private var color=0
    @State private var size:TileSize = .small
    @State private var column=0
    @State private var row=0
    var body:some View{
        NavigationStack{
            Form{
                Section("基本情報"){
                    TextField("タイル名",text:$title)
                    Picker("起動方法",selection:$launchMethod){
                        ForEach(AppLaunchMethod.allCases){method in Text(method.rawValue).tag(method)}
                    }
                    switch launchMethod{
                    case .bundleIdentifier:
                        TextField("Bundle ID",text:$bundleIdentifier).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Text("入力したBundle IDの末尾に自動で「://」を付けて起動するよ。例：com.example.app://").font(.caption).foregroundStyle(.secondary)
                        Text("※アプリ側がBundle IDと同じURLスキームを登録している場合だけ起動できるよ。Bundle IDだけで起動できるわけではないよ。").font(.caption).foregroundStyle(.orange)
                    case .urlScheme:
                        TextField("URLスキーム",text:$urlValue,prompt:Text("例：maps://")).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Text("アプリが対応しているURLスキームを入力してね。").font(.caption).foregroundStyle(.secondary)
                    case .universalLink:
                        TextField("URL",text:$urlValue,prompt:Text("https://example.com")).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Text("対応アプリがあるUniversal Linkならそのアプリが開き、なければWebページが開くよ。").font(.caption).foregroundStyle(.secondary)
                    case .shortcut:
                        TextField("ショートカット名",text:$shortcutName)
                        Text("ショートカットアプリで作成した名前を正確に入力してね。実行時はショートカットアプリに切り替わる場合があるよ。").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("タイルサイズ"){
                    Picker("サイズ",selection:$size){ForEach(TileSize.allCases){Text($0.rawValue).tag($0)}}.pickerStyle(.segmented)
                }
                Section("配置位置"){
                    Stepper("列：\(column+1)",value:$column,in:0...(4-size.columns))
                    Stepper("行：\(row+1)",value:$row,in:0...100)
                }
                Section("アイコン"){
                    let icons=["app","camera","photo","gearshape","moon","sun.max","bolt.fill","music.note","map","house","message","phone","globe","cloud","timer","heart","video","car","location","bell","wifi","bluetooth"]
                    LazyVGrid(columns:Array(repeating:GridItem(.flexible()),count:6)){
                        ForEach(icons,id:\.self){value in
                            Button{icon=value}label:{Image(systemName:value).font(.title2).frame(maxWidth:.infinity).padding(8).background(icon==value ? Color.blue.opacity(0.35):Color.clear).clipShape(RoundedRectangle(cornerRadius:8))}.buttonStyle(.plain)
                        }
                    }
                }
                Section("カラー"){
                    Picker("カラー",selection:$color){Text("ブルー").tag(0);Text("グリーン").tag(1);Text("パープル").tag(2);Text("オレンジ").tag(3);Text("シアン").tag(4)}
                }
            }
            .navigationTitle(existing == nil ? "起動タイル追加":"タイル編集").navigationBarTitleDisplayMode(.inline)
            .toolbar{
                ToolbarItem(placement:.cancellationAction){Button("キャンセル"){dismiss()}}
                ToolbarItem(placement:.confirmationAction){
                    Button("保存"){
                        let target:String
                        let kind:ButtonKind
                        let savedBundleID:String?
                        let savedShortcut:String?
                        switch launchMethod{
                        case .bundleIdentifier:
                            let clean=bundleIdentifier.trimmingCharacters(in:.whitespacesAndNewlines)
                            let identifier=clean.hasSuffix("://") ? String(clean.dropLast(3)):clean
                            target=identifier+"://";kind = .app;savedBundleID=identifier;savedShortcut=nil
                        case .urlScheme:
                            target=urlValue.trimmingCharacters(in:.whitespacesAndNewlines);kind = .app;savedBundleID=nil;savedShortcut=nil
                        case .universalLink:
                            let raw=urlValue.trimmingCharacters(in:.whitespacesAndNewlines)
                            target=(raw.contains("://") ? raw:"https://"+raw);kind = .app;savedBundleID=nil;savedShortcut=nil
                        case .shortcut:
                            target=shortcutName.trimmingCharacters(in:.whitespacesAndNewlines);kind = .shortcut;savedBundleID=nil;savedShortcut=target
                        }
                        onSave(PanelButton(id:existing?.id ?? UUID(),title:title.trimmingCharacters(in:.whitespacesAndNewlines),kind:kind,target:target,icon:icon,colorIndex:color,size:size,column:column,row:row,launchMethod:launchMethod,bundleIdentifier:savedBundleID,shortcutName:savedShortcut))
                        dismiss()
                    }.disabled(!canSave)
                }
            }
            .onAppear{loadExisting()}
            .onChange(of:size){column=min(column,4-size.columns)}
        }.preferredColorScheme(.dark)
    }
    private var canSave:Bool{
        guard !title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{return false}
        switch launchMethod{
        case .bundleIdentifier:return !bundleIdentifier.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty
        case .urlScheme,.universalLink:return !urlValue.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty
        case .shortcut:return !shortcutName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty
        }
    }
    private func loadExisting(){
        guard let existing else{return}
        title=existing.title;icon=existing.icon;color=existing.colorIndex;size=existing.size;column=existing.column;row=existing.row
        if let method=existing.launchMethod{
            launchMethod=method;bundleIdentifier=existing.bundleIdentifier ?? ""
            shortcutName=existing.shortcutName ?? (method == .shortcut ? existing.target:"")
            urlValue=method == .urlScheme || method == .universalLink ? existing.target:""
        }else if existing.kind == .shortcut || existing.kind == .setting{
            launchMethod = .shortcut;shortcutName=existing.shortcutName ?? existing.target
        }else if existing.target.lowercased().hasPrefix("http://") || existing.target.lowercased().hasPrefix("https://"){
            launchMethod = .universalLink;urlValue=existing.target
        }else{launchMethod = .urlScheme;urlValue=existing.target}
    }
}

struct WorkflowEditorView:View {
    var existing:ActionWorkflow
    let onSave:(ActionWorkflow)->Void
    @Environment(\.dismiss) private var dismiss
    @State private var title=""
    @State private var icon="bolt.fill"
    @State private var color=0
    @State private var actions:[ActionDefinition]=[]
    @State private var category:ActionCategory = .appScreen
    @State private var editingAction:ActionDefinition?
    @State private var showActionPicker=false
    var body:some View{
        NavigationStack{
            Form{
                Section("アクション名"){
                    TextField("例：仕事開始",text:$title)
                    Picker("タイルアイコン",selection:$icon){
                        ForEach(["bolt.fill","briefcase.fill","house.fill","sun.max.fill","moon.fill","wifi","bell.fill","globe","doc.text","gearshape.fill"],id:\.self){Image(systemName:$0).tag($0)}
                    }
                    Picker("追加するカテゴリー",selection:$category){ForEach(ActionCategory.allCases){Text($0.title).tag($0)}}
                }
                Section("実行する処理"){
                    ForEach(Array(actions.enumerated()),id:\.element.id){index,action in
                        Button{editingAction=action}label:{
                            HStack(spacing:12){
                                Text("\(index+1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width:22)
                                Image(systemName:ActionCatalog.descriptor(for:action.type)?.category.symbol ?? "bolt").frame(width:24)
                                VStack(alignment:.leading,spacing:3){
                                    Text(action.title).foregroundStyle(.primary)
                                    Text(action.category.title).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName:"chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .onDelete{actions.remove(atOffsets:$0)}
                    .onMove{actions.move(fromOffsets:$0,toOffset:$1)}
                    Button{showActionPicker=true}label:{Label("選択したカテゴリーから追加",systemImage:"plus.circle.fill")}
                }
                Section("タイルカラー"){
                    Picker("カラー",selection:$color){Text("ブルー").tag(0);Text("グリーン").tag(1);Text("パープル").tag(2);Text("オレンジ").tag(3);Text("シアン").tag(4)}
                }
                Section{
                    Text("上から順番に実行されるよ。アプリ起動や設定画面を開く処理は、基本的に最後に置いてね。").font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("アクションを作成").navigationBarTitleDisplayMode(.inline)
            .toolbar{
                ToolbarItem(placement:.cancellationAction){Button("キャンセル"){dismiss()}}
                ToolbarItem(placement:.principal){EditButton()}
                ToolbarItem(placement:.confirmationAction){
                    Button("保存"){
                        var workflow=existing
                        workflow.title=title.trimmingCharacters(in:.whitespacesAndNewlines)
                        workflow.icon=icon;workflow.colorIndex=color;workflow.actions=actions;workflow.touch()
                        onSave(workflow);dismiss()
                    }.disabled(title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || actions.isEmpty)
                }
            }
            .confirmationDialog("追加するアクション",isPresented:$showActionPicker,titleVisibility:.visible){
                ForEach(ActionCatalog.actions(in:category)){descriptor in
                    Button(descriptor.title){
                        let action=makeAction(descriptor);actions.append(action);editingAction=action
                    }
                }
                Button("キャンセル",role:.cancel){}
            }message:{Text("「\(category.title)」のアクションを選んでね。")}
            .sheet(item:$editingAction){action in
                ActionParameterEditor(action:action){updated in
                    if let i=actions.firstIndex(where:{$0.id==updated.id}){actions[i]=updated}
                }
            }
            .onAppear{title=existing.title;icon=existing.icon;color=existing.colorIndex;actions=existing.actions}
        }.preferredColorScheme(.dark)
    }
    private func makeAction(_ descriptor:ActionDescriptor)->ActionDefinition{
        var params:[String:ActionValue]=[:]
        for field in descriptor.fields{
            switch field.kind{
            case .choice,.systemSettingPicker,.appPicker:params[field.key] = .string(field.options.first?.value ?? "")
            case .toggle:params[field.key] = .bool(false)
            case .number,.duration:params[field.key] = .string("1")
            default:params[field.key] = .string("")
            }
        }
        return ActionDefinition(type:descriptor.type,category:descriptor.category,title:descriptor.title,parameters:params)
    }
}

struct ActionParameterEditor:View {
    @State var action:ActionDefinition
    let onSave:(ActionDefinition)->Void
    @Environment(\.dismiss) private var dismiss
    private var descriptor:ActionDescriptor?{ActionCatalog.descriptor(for:action.type)}
    var body:some View{
        NavigationStack{
            Form{
                Section{Text(action.title).font(.headline);Text(descriptor?.description ?? "").font(.caption).foregroundStyle(.secondary)}
                if let descriptor{ForEach(descriptor.fields){field in fieldEditor(field)}}
                Section("エラー時の動作"){
                    Picker("処理に失敗したら",selection:$action.failurePolicy){ForEach(ActionFailurePolicy.allCases){Text($0.title).tag($0)}}
                }
                Section("実行結果の保存（任意）"){
                    TextField("変数名",text:Binding(get:{action.outputVariable ?? ""},set:{action.outputVariable=$0.isEmpty ? nil:$0}))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
            }
            .navigationTitle("アクション設定").navigationBarTitleDisplayMode(.inline)
            .toolbar{
                ToolbarItem(placement:.cancellationAction){Button("戻る"){dismiss()}}
                ToolbarItem(placement:.confirmationAction){Button("完了"){onSave(action);dismiss()}}
            }
        }.preferredColorScheme(.dark)
    }
    @ViewBuilder private func fieldEditor(_ field:ActionFieldSchema)->some View{
        switch field.kind{
        case .choice,.systemSettingPicker,.appPicker:
            Picker(field.title,selection:stringBinding(field.key)){ForEach(field.options){Text($0.title).tag($0.value)}}
        case .toggle:
            Toggle(field.title,isOn:Binding(get:{action.parameters[field.key] == .bool(true)},set:{action.parameters[field.key] = .bool($0)}))
        case .multilineText:
            Section(field.title){TextEditor(text:stringBinding(field.key)).frame(minHeight:100)}
        case .number,.duration:
            TextField(field.title,text:stringBinding(field.key)).keyboardType(.decimalPad)
        case .url:
            TextField(field.title,text:stringBinding(field.key),prompt:Text(field.placeholder ?? "https://"))
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
        case .variableName:
            TextField(field.title,text:stringBinding(field.key),prompt:Text(field.placeholder ?? "variable"))
                .textInputAutocapitalization(.never).autocorrectionDisabled()
        case .shortText:
            TextField(field.title,text:stringBinding(field.key),prompt:Text(field.placeholder ?? "入力"))
        }
    }
    private func stringBinding(_ key:String)->Binding<String>{
        Binding(get:{action.parameters[key]?.displayString ?? ""},set:{action.parameters[key] = .string($0)})
    }
}
