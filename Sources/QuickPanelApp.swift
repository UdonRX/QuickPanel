
import SwiftUI
import UIKit
import Combine

// MARK: - Models

enum ButtonKind: String, CaseIterable, Codable, Identifiable {
    case app = "アプリ"
    case shortcut = "ショートカット"
    case setting = "設定・操作"

    var id: String { rawValue }
}

enum TileSize: String, CaseIterable, Codable, Identifiable {
    case small = "1×1"
    case wide = "2×1"
    case large = "2×2"

    var id: String { rawValue }

    var columns: Int {
        switch self {
        case .small: return 1
        case .wide, .large: return 2
        }
    }

    var rows: Int {
        switch self {
        case .small, .wide: return 1
        case .large: return 2
        }
    }
}

struct PanelButton: Identifiable, Codable {
    var id: UUID = UUID()
    var title: String
    var kind: ButtonKind
    var target: String
    var icon: String
    var colorIndex: Int
    var size: TileSize = .small
    var column: Int = 0
    var row: Int = 0
}

// MARK: - App presets

struct AppPreset: Identifiable {
    let id: String
    let name: String
    let scheme: String
    let icon: String
}

let appPresets: [AppPreset] = [
    .init(id: "settings", name: "設定", scheme: "App-Prefs:", icon: "gear"),
    .init(id: "camera", name: "カメラ", scheme: "camera:", icon: "camera"),
    .init(id: "photos", name: "写真", scheme: "photos-redirect:", icon: "photo"),
    .init(id: "maps", name: "マップ", scheme: "maps:", icon: "map"),
    .init(id: "music", name: "ミュージック", scheme: "music:", icon: "music.note"),
    .init(id: "safari", name: "Safari", scheme: "https://www.apple.com", icon: "safari"),
    .init(id: "phone", name: "電話", scheme: "tel:", icon: "phone"),
    .init(id: "messages", name: "メッセージ", scheme: "sms:", icon: "message")
]

// MARK: - Store

@MainActor
final class PanelStore: ObservableObject {

    @Published var buttons: [PanelButton] = [] {
        didSet { save() }
    }

    private let key = "QuickPanel.Buttons.v2"

    init() {
        load()
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return
        }

        if let decoded = try? JSONDecoder().decode(
            [PanelButton].self,
            from: data
        ) {
            buttons = decoded
        }
    }

    func save() {
        guard let data = try? JSONEncoder().encode(buttons) else {
            return
        }
        UserDefaults.standard.set(data, forKey: key)
    }

    func add(_ button: PanelButton) {
        var new = button
        new.id = UUID()

        let position = firstFreePosition(
            column: new.column,
            row: new.row,
            size: new.size,
            excluding: nil
        )

        new.column = position.0
        new.row = position.1
        buttons.append(new)
    }

    func update(_ button: PanelButton) {
        guard let index = buttons.firstIndex(
            where: { $0.id == button.id }
        ) else { return }

        buttons[index] = button
        normalizePositions()
    }

    func duplicate(_ button: PanelButton) {
        var copy = button
        copy.id = UUID()
        copy.title += " コピー"

        let position = firstFreePosition(
            column: button.column + button.size.columns,
            row: button.row,
            size: button.size,
            excluding: nil
        )

        copy.column = position.0
        copy.row = position.1
        buttons.append(copy)
    }

    func delete(_ button: PanelButton) {
        buttons.removeAll { $0.id == button.id }
    }

    func move(
        _ button: PanelButton,
        column: Int,
        row: Int
    ) {
        guard let index = buttons.firstIndex(
            where: { $0.id == button.id }
        ) else { return }

        let position = firstFreePosition(
            column: column,
            row: row,
            size: button.size,
            excluding: button.id
        )

        buttons[index].column = position.0
        buttons[index].row = position.1
    }

    func changeSize(_ button: PanelButton, size: TileSize) {
        guard let index = buttons.firstIndex(
            where: { $0.id == button.id }
        ) else { return }

        buttons[index].size = size

        let position = firstFreePosition(
            column: button.column,
            row: button.row,
            size: size,
            excluding: button.id
        )

        buttons[index].column = position.0
        buttons[index].row = position.1
    }

    private func firstFreePosition(
        column: Int,
        row: Int,
        size: TileSize,
        excluding: UUID?
    ) -> (Int, Int) {

        let startColumn = min(max(0, column), 4 - size.columns)
        let startRow = max(0, row)

        for r in startRow...(startRow + 500) {
            for c in 0...(4 - size.columns) {
                let actualColumn = r == startRow
                    ? max(startColumn, c)
                    : c

                if actualColumn > 4 - size.columns { continue }

                if isFree(
                    column: actualColumn,
                    row: r,
                    size: size,
                    excluding: excluding
                ) {
                    return (actualColumn, r)
                }
            }
        }

        return (0, startRow + 501)
    }

    private func isFree(
        column: Int,
        row: Int,
        size: TileSize,
        excluding: UUID?
    ) -> Bool {

        for item in buttons where item.id != excluding {
            let horizontalOverlap =
                column < item.column + item.size.columns &&
                column + size.columns > item.column

            let verticalOverlap =
                row < item.row + item.size.rows &&
                row + size.rows > item.row

            if horizontalOverlap && verticalOverlap {
                return false
            }
        }

        return true
    }

    private func normalizePositions() {
        let old = buttons
        buttons = []

        for item in old {
            var copy = item

            let position = firstFreePosition(
                column: copy.column,
                row: copy.row,
                size: copy.size,
                excluding: nil
            )

            copy.column = position.0
            copy.row = position.1
            buttons.append(copy)
        }
    }
}

// MARK: - App

@main
struct QuickPanelApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Main View

struct MainView: View {

    @StateObject private var store = PanelStore()

    @State private var showEditor = false
    @State private var editingButton: PanelButton?
    @State private var isEditing = false

    private let spacing: CGFloat = 10
    private let sidePadding: CGFloat = 16

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in

                let unit = (
                    geometry.size.width
                    - sidePadding * 2
                    - spacing * 3
                ) / 4

                let rowHeight = unit + spacing

                ScrollView {
                    ZStack(alignment: .topLeading) {

                        // 空の配置スペース
                        Color.clear
                            .frame(
                                height: max(
                                    350,
                                    CGFloat(maxRow + 1) * rowHeight
                                )
                            )

                        ForEach(store.buttons) { item in
                            TileView(
                                item: item,
                                editing: isEditing,
                                unit: unit,
                                spacing: spacing,
                                editAction: {
                                    editingButton = item
                                },
                                duplicateAction: {
                                    store.duplicate(item)
                                },
                                deleteAction: {
                                    store.delete(item)
                                },
                         moveAction: { x, y in
    let col = item.column + Int(round(x / rowHeight))
    let row = item.row + Int(round(y / rowHeight))
                                    )

                                    store.move(
                                        item,
                                        column: col,
                                        row: row
                                    )
                                }
                            )
                            .frame(
                                width: CGFloat(item.size.columns) * unit
                                    + CGFloat(item.size.columns - 1) * spacing,
                                height: CGFloat(item.size.rows) * unit
                                    + CGFloat(item.size.rows - 1) * spacing
                            )
                            .position(
                                x: sidePadding
                                    + CGFloat(item.column) * rowHeight
                                    + (
                                        CGFloat(item.size.columns) * unit
                                        + CGFloat(item.size.columns - 1) * spacing
                                    ) / 2,
                                y: CGFloat(item.row) * rowHeight
                                    + (
                                        CGFloat(item.size.rows) * unit
                                        + CGFloat(item.size.rows - 1) * spacing
                                    ) / 2
                            )
                        }
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 30)
                }
            }
            .background(Color(red: 0.055, green: 0.065, blue: 0.085))
            .navigationTitle("QuickPanel")
            .toolbar {

                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isEditing.toggle()
                    } label: {
                        Image(systemName: "square.grid.2x2")
                            .font(.title2)
                            .foregroundStyle(
                                isEditing ? .orange : .white
                            )
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editingButton = nil
                        showEditor = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
                }
            }
            .sheet(isPresented: $showEditor) {
                ButtonEditorView { button in
                    store.add(button)
                }
            }
            .sheet(item: $editingButton) { button in
                ButtonEditorView(existing: button) { updated in
                    store.update(updated)
                }
            }
            .overlay {
                if store.buttons.isEmpty {
                    ContentUnavailableView(
                        "ボタンがありません",
                        systemImage: "square.grid.2x2",
                        description: Text("右上の＋から追加してね")
                    )
                }
            }
        }
    }

    private var maxRow: Int {
        store.buttons.map {
            $0.row + $0.size.rows
        }.max() ?? 3
    }
}

// MARK: - Tile

struct TileView: View {

    let item: PanelButton
    let editing: Bool
    let unit: CGFloat
    let spacing: CGFloat

    let editAction: () -> Void
    let duplicateAction: () -> Void
    let deleteAction: () -> Void
    let moveAction: (CGFloat, CGFloat) -> Void

    @Environment(\.openURL) private var openURL

    @State private var dragOffset: CGSize = .zero

    private let colors: [Color] = [
        Color(red: 0.14, green: 0.23, blue: 0.34),
        Color(red: 0.18, green: 0.29, blue: 0.24),
        Color(red: 0.29, green: 0.23, blue: 0.36),
        Color(red: 0.35, green: 0.27, blue: 0.18),
        Color(red: 0.17, green: 0.29, blue: 0.34)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            HStack {
                Image(systemName: item.icon)
                    .font(.system(size: 27, weight: .medium))

                Spacer()

                if editing {
                    Menu {
                        Button("編集", systemImage: "pencil") {
                            editAction()
                        }

                        Button("複製", systemImage: "plus.square.on.square") {
                            duplicateAction()
                        }

                        Divider()

                        Button(
                            "削除",
                            systemImage: "trash",
                            role: .destructive
                        ) {
                            deleteAction()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title2)
                    }
                }
            }

            Spacer(minLength: 2)

            Text(item.title)
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(2)

            Text(item.kind.rawValue + "  ·  " + item.size.rawValue)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.65))
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            colors[item.colorIndex % colors.count]
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay {
            if editing {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(.white.opacity(0.35), style: StrokeStyle(
                        lineWidth: 1,
                        dash: [5]
                    ))
            }
        }
        .offset(dragOffset)
.simultaneousGesture(
    DragGesture(minimumDistance: editing ? 5 : 100000)
        .onChanged { value in
            dragOffset = value.translation
        }
        .onEnded { value in
            if editing {
                moveAction(
                    value.translation.width,
                    value.translation.height
                )
            }
            dragOffset = .zero
        }
)
        .onTapGesture {
            if !editing {
                execute()
            }
        }
        .contextMenu {
            Button("編集", systemImage: "pencil") {
                editAction()
            }

            Button("複製", systemImage: "plus.square.on.square") {
                duplicateAction()
            }

            Button("削除", systemImage: "trash", role: .destructive) {
                deleteAction()
            }
        }
    }

    private func execute() {
        switch item.kind {

        case .app:
            guard let url = URL(string: item.target) else { return }
            openURL(url)

        case .shortcut, .setting:
            var components = URLComponents()
            components.scheme = "shortcuts"
            components.host = "run-shortcut"
            components.queryItems = [
                URLQueryItem(name: "name", value: item.target)
            ]

            if let url = components.url {
                openURL(url)
            }
        }
    }
}

// MARK: - Add / Edit

struct ButtonEditorView: View {

    var existing: PanelButton? = nil
    let onSave: (PanelButton) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var kind: ButtonKind = .app
    @State private var target = ""
    @State private var icon = "app"
    @State private var colorIndex = 0
    @State private var size: TileSize = .small
    @State private var column = 0
    @State private var row = 0

    private let icons = [
        "app", "camera", "photo", "wifi",
        "bluetooth", "gearshape", "moon",
        "sun.max", "bolt.fill", "music.note",
        "map", "house", "message", "phone",
        "globe", "cloud", "timer", "heart",
        "video", "car", "location", "bell"
    ]

    var body: some View {
        NavigationStack {
            Form {

                Section("基本情報") {
                    TextField("ボタン名", text: $title)

                    Picker("種類", selection: $kind) {
                        ForEach(ButtonKind.allCases) { value in
                            Text(value.rawValue).tag(value)
                        }
                    }
                    .onChange(of: kind) {
                        target = ""
                    }
                }

                if kind == .app {
                    Section("アプリ候補") {
                        ForEach(appPresets) { preset in
                            Button {
                                target = preset.scheme
                                if title.isEmpty {
                                    title = preset.name
                                }
                                icon = preset.icon
                            } label: {
                                HStack {
                                    Image(systemName: preset.icon)
                                        .frame(width: 28)

                                    Text(preset.name)

                                    Spacer()

                                    if target == preset.scheme {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }

                    Section("アプリ起動URL") {
                        TextField(
                            "例：myapp://",
                            text: $target
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        Text("候補にないアプリは、アプリ提供元が公開しているURLスキームを入力してね。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section(
                        kind == .setting
                            ? "設定操作用ショートカット"
                            : "ショートカット"
                    ) {
                        TextField(
                            "ショートカット名",
                            text: $target
                        )

                        Text("ショートカットアプリで作成した名前を正確に入力してね。")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button("ショートカットアプリを開く") {
                            if let url = URL(string: "shortcuts://") {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                }

                Section("タイルサイズ") {
                    Picker("サイズ", selection: $size) {
                        ForEach(TileSize.allCases) { value in
                            Text(value.rawValue).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("配置位置") {
                    Stepper(
                        "列：\(column + 1)",
                        value: $column,
                        in: 0...(4 - size.columns)
                    )

                    Stepper(
                        "行：\(row + 1)",
                        value: $row,
                        in: 0...100
                    )
                }

                Section("アイコン") {
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible()),
                            count: 6
                        )
                    ) {
                        ForEach(icons, id: \.self) { value in
                            Button {
                                icon = value
                            } label: {
                                Image(systemName: value)
                                    .font(.title2)
                                    .frame(maxWidth: .infinity)
                                    .padding(8)
                                    .background(
                                        icon == value
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

                Section("カラー") {
                    Picker("カラー", selection: $colorIndex) {
                        Text("ブルー").tag(0)
                        Text("グリーン").tag(1)
                        Text("パープル").tag(2)
                        Text("オレンジ").tag(3)
                        Text("シアン").tag(4)
                    }
                }
            }
            .navigationTitle(existing == nil ? "ボタン追加" : "ボタン編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {

                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let button = PanelButton(
                            id: existing?.id ?? UUID(),
                            title: title.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ),
                            kind: kind,
                            target: target.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ),
                            icon: icon,
                            colorIndex: colorIndex,
                            size: size,
                            column: column,
                            row: row
                        )

                        onSave(button)
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
            .onAppear {
                guard let existing else { return }

                title = existing.title
                kind = existing.kind
                target = existing.target
                icon = existing.icon
                colorIndex = existing.colorIndex
                size = existing.size
                column = existing.column
                row = existing.row
            }
            .onChange(of: size) {
                column = min(column, 4 - size.columns)
            }
        }
        .preferredColorScheme(.dark)
    }
}
