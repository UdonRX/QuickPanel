
import SwiftUI

// MARK: - データモデル

enum ButtonKind: String, CaseIterable, Codable, Identifiable {
    case app = "アプリ"
    case shortcut = "ショートカット"
    case setting = "iPhone設定"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .app: return "app"
        case .shortcut: return "bolt.fill"
        case .setting: return "gearshape.fill"
        }
    }
}

struct PanelButton: Identifiable, Codable {
    var id = UUID()
    var title: String
    var kind: ButtonKind
    var target: String
    var icon: String
    var colorIndex: Int
}

// MARK: - 保存・実行

@MainActor
final class PanelStore: ObservableObject {
    @Published var buttons: [PanelButton] = [] {
        didSet { save() }
    }

    private let storageKey = "QuickPanel.Buttons"

    init() {
        load()
    }

    func load() {
        guard let data = UserDefaults.standard.data(
            forKey: storageKey
        ) else { return }

        do {
            buttons = try JSONDecoder().decode(
                [PanelButton].self,
                from: data
            )
        } catch {
            buttons = []
        }
    }

    func save() {
        guard let data = try? JSONEncoder().encode(buttons) else {
            return
        }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    func add(_ button: PanelButton) {
        buttons.append(button)
    }

    func delete(_ button: PanelButton) {
        buttons.removeAll { $0.id == button.id }
    }

    func move(from source: UUID, to destination: UUID) {
        guard
            let from = buttons.firstIndex(where: { $0.id == source }),
            let to = buttons.firstIndex(where: { $0.id == destination }),
            from != to
        else { return }

        let item = buttons.remove(at: from)
        let newIndex = buttons.firstIndex(
            where: { $0.id == destination }
        ) ?? min(to, buttons.count)

        buttons.insert(item, at: newIndex)
    }
}

// MARK: - メインアプリ

@main
struct QuickPanelApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - メイン画面

struct MainView: View {
    @StateObject private var store = PanelStore()
    @State private var showAdd = false
    @State private var editing = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(store.buttons) { item in
                        TileView(
                            item: item,
                            editing: editing,
                            deleteAction: {
                                store.delete(item)
                            }
                        )
                        .draggable(item.id.uuidString)
                        .dropDestination(for: String.self) {
                            values, _ in

                            guard
                                editing,
                                let value = values.first,
                                let source = UUID(uuidString: value)
                            else { return false }

                            store.move(
                                from: source,
                                to: item.id
                            )
                            return true
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .background(Color(red: 0.055, green: 0.065, blue: 0.085))
            .navigationTitle("QuickPanel")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation {
                            editing.toggle()
                        }
                    } label: {
                        Image(systemName: "square.grid.2x2")
                            .font(.title2)
                            .foregroundStyle(
                                editing ? .orange : .white
                            )
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddButtonView { newButton in
                    store.add(newButton)
                }
            }
            .overlay {
                if store.buttons.isEmpty {
                    ContentUnavailableView(
                        "ボタンがありません",
                        systemImage: "square.grid.2x2",
                        description: Text("右上の＋からボタンを追加してね")
                    )
                }
            }
        }
    }
}

// MARK: - Bentoタイル

struct TileView: View {
    let item: PanelButton
    let editing: Bool
    let deleteAction: () -> Void

    @Environment(\.openURL) private var openURL

    private let colors: [Color] = [
        Color(red: 0.14, green: 0.23, blue: 0.34),
        Color(red: 0.18, green: 0.29, blue: 0.24),
        Color(red: 0.29, green: 0.23, blue: 0.36),
        Color(red: 0.35, green: 0.27, blue: 0.18),
        Color(red: 0.17, green: 0.29, blue: 0.34)
    ]

    var body: some View {
        Button {
            if !editing {
                execute()
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: item.icon)
                        .font(.system(size: 25, weight: .medium))
                        .foregroundStyle(.white)

                    Spacer()

                    if editing {
                        Image(systemName: "arrow.up.arrow.down")
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }

                Spacer(minLength: 4)

                Text(item.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text(item.kind.rawValue)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 125)
            .background(
                colors[item.colorIndex % colors.count]
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(alignment: .topTrailing) {
                if editing {
                    Button(action: deleteAction) {
                        Image(systemName: "minus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.red)
                            .background(.white, in: Circle())
                    }
                    .offset(x: 7, y: -7)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func execute() {
        var url: URL?

        switch item.kind {
        case .app:
            url = URL(string: item.target)

        case .shortcut, .setting:
            var components = URLComponents()
            components.scheme = "shortcuts"
            components.host = "run-shortcut"
            components.queryItems = [
                URLQueryItem(
                    name: "name",
                    value: item.target
                )
            ]
            url = components.url
        }

        guard let url else { return }
        openURL(url)
    }
}

// MARK: - ボタン追加画面

struct AddButtonView: View {
    let onAdd: (PanelButton) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var target = ""
    @State private var icon = "square"
    @State private var kind: ButtonKind = .shortcut
    @State private var colorIndex = 0

    private let icons = [
        "app", "camera", "photo",
        "wifi", "bluetooth", "gearshape",
        "moon", "sun.max", "bolt.fill",
        "music.note", "map", "house",
        "message", "phone", "globe",
        "cloud", "timer", "heart"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("基本情報") {
                    TextField("ボタンの名前", text: $title)

                    Picker("種類", selection: $kind) {
                        ForEach(ButtonKind.allCases) { item in
                            Text(item.rawValue)
                                .tag(item)
                        }
                    }
                }

                Section("起動先") {
                    TextField(
                        kind == .app
                            ? "アプリのURLスキーム"
                            : "ショートカットの名前",
                        text: $target
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    if kind == .app {
                        Text("例：アプリが対応しているURLスキームやUniversal Linkを入力")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("ショートカットアプリに登録した名前と完全に一致させてね")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("アイコン") {
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible()),
                            count: 6
                        )
                    ) {
                        ForEach(icons, id: \.self) { symbol in
                            Button {
                                icon = symbol
                            } label: {
                                Image(systemName: symbol)
                                    .font(.title2)
                                    .frame(maxWidth: .infinity)
                                    .padding(8)
                                    .background(
                                        icon == symbol
                                            ? Color.blue.opacity(0.35)
                                            : Color.clear
                                    )
                                    .clipShape(RoundedRectangle(
                                        cornerRadius: 8
                                    ))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("タイルカラー") {
                    Picker("カラー", selection: $colorIndex) {
                        Text("ブルー").tag(0)
                        Text("グリーン").tag(1)
                        Text("パープル").tag(2)
                        Text("オレンジ").tag(3)
                        Text("シアン").tag(4)
                    }
                }
            }
            .navigationTitle("ボタンを追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") {
                        let newButton = PanelButton(
                            title: title,
                            kind: kind,
                            target: target,
                            icon: icon,
                            colorIndex: colorIndex
                        )

                        onAdd(newButton)
                        dismiss()
                    }
                    .disabled(
                        title.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty ||
                        target.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                    )
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
