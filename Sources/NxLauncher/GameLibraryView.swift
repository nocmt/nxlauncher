import AppKit
import SwiftUI

struct GameLibraryView: View {
    @EnvironmentObject var state: LauncherState
    var openWorkspace: () -> Void
    var addGame: () -> Void
    var openSettings: () -> Void
    @State private var query = ""
    @State private var removal: LibraryGame?

    private var visibleGames: [LibraryGame] {
        state.library.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
            || $0.titleID.localizedCaseInsensitiveContains(query) }
    }

    private var selected: LibraryGame? {
        state.library.first { $0.id == state.selectedGameID }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 24)).foregroundStyle(DS.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("NxLauncher").font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text("游戏库").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                StatusDot(text: state.checkingDependencies ? "检查编译环境…" :
                            (state.dependencies?.ready == true ? "编译环境已就绪" : "查看编译环境"),
                          color: state.dependencies?.ready == true ? DS.ok : DS.warn)
                Button(action: openSettings) { Image(systemName: "gearshape").font(.system(size: 16)) }
                    .buttonStyle(QuietButtonStyle()).help("通用设置与编译环境")
                    .accessibilityLabel("通用设置")
            }
            .padding(.horizontal, 26).padding(.vertical, 20)
            Divider()
            GeometryReader { geometry in
                HStack(alignment: .top, spacing: 24) {
                    library(showOpenButton: geometry.size.width < 960)
                    if geometry.size.width >= 960 {
                        Color.clear.frame(width: 300)
                            .overlay(alignment: .top) { detail }
                    }
                }
                .padding(26)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .background(LinearGradient(colors: [DS.windowTop, DS.windowBottom], startPoint: .topLeading, endPoint: .bottomTrailing))
        .confirmationDialog("从游戏库移除？", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }), titleVisibility: .visible) {
            if let game = removal {
                Button("移除记录", role: .destructive) { state.removeGame(game); removal = nil }
            }
            Button("取消", role: .cancel) { removal = nil }
        } message: {
            Text("仅移除游戏库记录。游戏文件、编译结果和存档都会保留。")
        }
    }

    private func library(showOpenButton: Bool) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("我的游戏").font(.system(size: 23, weight: .semibold))
                Text("\(state.library.count) 款").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索游戏", text: $query).textFieldStyle(.plain)
                }
                .padding(8).frame(width: 170)
                .background(DS.quiet.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }
            if state.busy {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("\(selected?.name ?? "游戏") · \(state.statusText)", systemImage: "hammer.fill")
                            .font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Spacer()
                        Button("查看进度", action: openWorkspace).buttonStyle(QuietButtonStyle())
                    }
                    Bar(fraction: state.fraction ?? -1, height: 4)
                }
                .padding(14).background(DS.card, in: RoundedRectangle(cornerRadius: 12))
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 18, alignment: .top)], alignment: .leading, spacing: 24) {
                    ForEach(visibleGames) { game in
                        gameTile(game)
                    }
                    addTile
                }
                .padding(3)
                if visibleGames.isEmpty && !query.isEmpty {
                    Text("没有找到匹配的游戏").foregroundStyle(.secondary).padding(.top, 24)
                }
                if showOpenButton, let selected {
                    HStack(spacing: 10) {
                        Text(selected.name).lineLimit(1).foregroundStyle(.secondary)
                        Spacer()
                        Button("打开工作区", action: openWorkspace).buttonStyle(QuietButtonStyle())
                    }
                    .padding(.top, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func gameTile(_ game: LibraryGame) -> some View {
        Button {
            state.toggleGameSelection(game)
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                GameArtwork(path: game.icon)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 17))
                    .overlay(alignment: .bottomLeading) {
                        Text(game.built ? "已编译" : "待编译")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.regularMaterial, in: Capsule()).padding(10)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 17)
                            .strokeBorder(state.selectedGameID == game.id ? DS.accent : DS.cardStroke,
                                          lineWidth: 3)
                    }
                Text(game.name.isEmpty ? URL(fileURLWithPath: game.folder).lastPathComponent : game.name)
                    .font(.system(size: 13, weight: .semibold)).lineLimit(2)
                    .frame(height: 34, alignment: .topLeading)
                Text(game.version.isEmpty ? "尚未读取版本" : game.version)
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(state.busy)
        .help(game.folder)
        .contextMenu {
            Button("打开工作区") { state.selectGame(game); openWorkspace() }
            Button("在 Finder 中显示") { state.revealGameFolder(game) }
            Divider()
            Button("从游戏库移除…", role: .destructive) { removal = game }
        }
        .accessibilityLabel("\(game.name)，\(game.built ? "已编译" : "待编译")")
    }

    private var addTile: some View {
        Button(action: addGame) {
            VStack(alignment: .leading, spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 17).fill(DS.accent.opacity(0.025))
                    RoundedRectangle(cornerRadius: 17).strokeBorder(DS.accent.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                    VStack(spacing: 9) {
                        Image(systemName: "plus").font(.system(size: 28, weight: .light))
                        Text("选择游戏文件夹").font(.system(size: 11))
                    }
                    .foregroundStyle(DS.accent)
                }
                .aspectRatio(1, contentMode: .fit)
                Text("添加游戏").font(.system(size: 13, weight: .semibold)).frame(height: 34, alignment: .topLeading)
                Text(" ").font(.system(size: 11)).lineLimit(1).hidden().accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain).disabled(state.busy)
    }

    @ViewBuilder private var detail: some View {
        if let game = selected {
            Card(title: "游戏详情", systemImage: "info.circle") {
                HStack(alignment: .top, spacing: 12) {
                    GameArtwork(path: game.icon).frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(game.name).font(.system(size: 16, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true).lineLimit(4)
                        StatusDot(text: game.built ? "已编译" : "尚未编译", color: game.built ? DS.ok : DS.warn)
                    }
                }
                Divider()
                detailLine("版本", game.version.isEmpty ? "尚未读取" : game.version)
                detailLine("Title ID", game.titleID.isEmpty ? "尚未识别" : game.titleID)
                Text(game.folder).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    .textSelection(.enabled).lineLimit(3).truncationMode(.middle)
                Button(action: openWorkspace) { Label("打开工作区", systemImage: "arrow.right") }
                    .buttonStyle(PrimaryButtonStyle(enabled: !state.busy)).disabled(state.busy)
                if game.built {
                    Button { state.launchGame() } label: { Label("开始游戏", systemImage: "play.fill") }
                        .buttonStyle(SecondaryButtonStyle()).disabled(state.busy)
                }
                Button { state.revealGameFolder(game) } label: { Label("在 Finder 中显示", systemImage: "folder") }
                    .buttonStyle(QuietButtonStyle())
                Divider()
                Button("从游戏库移除…", role: .destructive) { removal = game }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(DS.bad).disabled(state.busy)
            }
        }
    }

    private func detailLine(_ name: String, _ value: String) -> some View {
        HStack {
            Text(name).foregroundStyle(.secondary)
            Spacer()
            Text(value).textSelection(.enabled).lineLimit(1)
        }.font(.system(size: 11))
    }
}

struct GameArtwork: View {
    var path: String
    var body: some View {
        GeometryReader { geo in
            if !path.isEmpty, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image).resizable().scaledToFill().frame(width: geo.size.width, height: geo.size.height).clipped()
            } else {
                ZStack {
                    LinearGradient(colors: [DS.accent.opacity(0.18), DS.card], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "gamecontroller").font(.system(size: min(geo.size.width, geo.size.height) * 0.3, weight: .light)).foregroundStyle(DS.accent)
                }
            }
        }
    }
}
