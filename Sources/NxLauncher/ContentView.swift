// The window: the game folder and what is in it, the settings, and the buttons.
import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: LauncherState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                gameData
                settings
                actions
                progress
            }
            .padding(20)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            state.loadGames()
            if !state.gameDir.isEmpty { state.refreshPlan() }
        }
    }

    // MARK: - header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(state.plan?.name ?? "NxLauncher")
                    .font(.system(size: 26, weight: .semibold))
                Text(state.statusText)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: $state.language) {
                ForEach(LauncherState.Language.allCases) { l in Text(l.rawValue).tag(l) }
            }
            .labelsHidden()
            .frame(width: 150)
            .onChange(of: state.language) { _, _ in state.writeEnv() }
        }
    }

    private var icon: some View {
        Group {
            if let path = state.plan?.icon, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "gamecontroller").resizable().aspectRatio(contentMode: .fit).foregroundStyle(.secondary)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - the game folder

    private var gameData: some View {
        card("游戏数据", systemImage: "folder") {
            HStack {
                Text(state.gameDir.isEmpty ? "还没有选择文件夹" : state.gameDir)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(state.gameDir.isEmpty ? .secondary : .primary)
                Spacer()
                Button("打开") { state.refreshPlan() }.disabled(state.gameDir.isEmpty)
                Button("选择…") { pickGameFolder() }
            }
            .padding(.bottom, 6)

            VStack(spacing: 0) {
                fileRow("游戏本体", state.plan?.base ?? "", ok: !(state.plan?.base ?? "").isEmpty)
                Divider()
                fileRow("更新包", (state.plan?.updates ?? []).first.map(Plan.fileName) ?? "",
                        ok: !(state.plan?.updates ?? []).isEmpty)
                Divider()
                fileRow("追加内容", (state.plan?.dlc ?? []).map(Plan.fileName).joined(separator: ", "),
                        ok: !(state.plan?.dlc ?? []).isEmpty)
                Divider()
                fileRow("Mac 游戏代码", state.plan?.hasPort == true ? "已就绪 · \(state.plan?.version ?? "")" : "没有移植档案",
                        ok: state.plan?.hasPort == true)
                Divider()
                fileRow("着色器缓存", state.plan?.built == true ? "已编译（可直接导出）" : "未编译（首次要 30–60 分钟）",
                        ok: state.plan?.built == true)
                Divider()
                HStack {
                    Label("主机密钥", systemImage: "key")
                    Spacer()
                    Text(state.keysPath.isEmpty ? "还没有选择" : (state.keysPath as NSString).lastPathComponent)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Button("选择…") { pickKeys() }
                }
                .padding(.vertical, 7)
                Divider()
                HStack {
                    Label("固件", systemImage: "cpu")
                    Spacer()
                    Text("不需要（流水线只认 prod.keys）").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .padding(.vertical, 7)
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.4), in: RoundedRectangle(cornerRadius: 8))

            if let notes = state.plan?.notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(notes, id: \.self) { n in
                        Text("· " + n).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    private func fileRow(_ title: String, _ detail: String, ok: Bool) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(ok ? Color.green : Color.secondary)
            Text(title)
            Spacer()
            Text(detail.isEmpty ? "—" : detail)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    // MARK: - the settings

    private var settings: some View {
        card("设置", systemImage: "slider.horizontal.3") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    Text("目标帧率")
                    Picker("", selection: $state.targetFPS) {
                        Text("60 帧").tag(60)
                        Text("30 帧（省电）").tag(30)
                    }
                    .labelsHidden()
                    .frame(width: 180)
                    .onChange(of: state.targetFPS) { _, _ in state.writeEnv() }
                }
                GridRow {
                    Text("导出目录")
                    Text(state.exportDir)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("选择…") { pickExportDir() }
                }
                GridRow {
                    Text("工具目录")
                    Text(state.home.path)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("重新读取") { state.refreshPlan() }
                }
            }
        }
    }

    // MARK: - the buttons

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                if state.plan?.built == true { state.launchGame() } else { state.startBuild() }
            } label: {
                Label(state.plan?.built == true ? "开始游戏" : "开始编译", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(state.busy)

            Button { state.exportMacApp() } label: {
                Label("导出 .app", systemImage: "app.dashed")
            }
            .controlSize(.large)
            .disabled(state.busy || state.plan?.built != true)

            Button { state.exportUnsignedIPA() } label: {
                Label("导出 IPA", systemImage: "square.and.arrow.down")
            }
            .controlSize(.large)
            .disabled(state.busy || state.plan?.built != true)
        }
    }

    // MARK: - the progress

    private var progress: some View {
        card("进度", systemImage: "chart.bar") {
            if let f = state.fraction {
                ProgressView(value: f) { Text(state.stageName) } currentValueLabel: {
                    Text("\(Int(f * 100))%")
                }
            } else if !state.stageName.isEmpty {
                ProgressView() { Text(state.stageName) }
            } else {
                Text(state.stepName.isEmpty ? "空闲" : state.stepName)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            if !state.progressNote.isEmpty {
                Text(state.progressNote).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(state.logLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(line.hasPrefix("✗") ? .red : .secondary)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 90, maxHeight: 180)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            .padding(.top, 4)
        }
    }

    // MARK: - the card

    private func card<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 14, weight: .medium))
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - the panels

    private func pickGameFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        if panel.runModal() == .OK, let url = panel.url {
            state.gameDir = url.path
            state.refreshPlan()
        }
    }

    private func pickKeys() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        if panel.runModal() == .OK, let url = panel.url {
            state.keysPath = url.path
            state.refreshPlan()
        }
    }

    private func pickExportDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "选择"
        if panel.runModal() == .OK, let url = panel.url {
            state.exportDir = url.path
        }
    }
}
