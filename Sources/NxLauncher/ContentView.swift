// The window: the game folder and what is in it, the settings, and the buttons.
import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: LauncherState

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    progressStrip
                    gameData
                    settings
                    log
                }
                .padding(18)
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(
                LinearGradient(colors: [Color(nsColor: .windowBackgroundColor),
                                        Color(nsColor: .underPageBackgroundColor).opacity(0.35)],
                               startPoint: .top, endPoint: .bottom)
            )
            Divider()
            actionBar
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.bar)
        }
        .onAppear {
            state.loadGames()
            if !state.gameDir.isEmpty { state.refreshPlan() }
        }
    }

    // MARK: - the progress strip (always visible)

    private var progressStrip: some View {
        HStack(spacing: 10) {
            Text(state.stageName.isEmpty ? (state.busy ? "运行中" : "空闲 · 等待操作") : state.stageName)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 90, alignment: .leading)
                .lineLimit(1)
            if !state.stepName.isEmpty {
                Text(state.stepName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let f = state.fraction {
                Text("\(Int(f * 100))%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else if state.busy {
                Text("…")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: DS.small, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.small, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .overlay(alignment: .bottom) {
            // nil = idle (an empty groove), a negative number = the count is unknown (a moving stripe).
            Bar(fraction: state.busy ? (state.fraction ?? -1) : nil, height: 2.5)
                .clipShape(RoundedRectangle(cornerRadius: DS.small, style: .continuous))
                .padding(.horizontal, 1)
                .offset(y: 1)
        }
    }

    // MARK: - header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            icon
            VStack(alignment: .leading, spacing: 3) {
                Text(state.plan?.name ?? "NxLauncher")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                StatusDot(text: statusLine, color: statusColor)
            }
            Spacer(minLength: 10)
            Picker("", selection: $state.language) {
                ForEach(LauncherState.Language.allCases) { l in Text(l.rawValue).tag(l) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 140)
            .onChange(of: state.language) { _, _ in state.writeEnv() }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }

    private var statusLine: String {
        if state.busy { return state.statusText }
        guard let p = state.plan else { return "还没有选择游戏文件夹" }
        if !p.repoOK { return "找不到 nxnative 源码目录" }
        if p.built { return "已就绪 · \(p.version)" }
        return "还没有编译过"
    }

    private var statusColor: Color {
        if state.busy { return DS.warn }
        guard let p = state.plan else { return DS.idle }
        if !p.repoOK { return DS.bad }
        return p.built ? DS.ok : DS.warn
    }

    private var icon: some View {
        Group {
            if let path = state.plan?.icon, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(DS.tint(DS.accent))
                    Image(systemName: "gamecontroller")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(DS.accent)
                }
            }
        }
        .frame(width: 58, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
    }

    // MARK: - the game folder

    private var gameData: some View {
        Card(title: "游戏数据", systemImage: "folder") {
            HStack(spacing: 8) {
                Text(state.gameDir.isEmpty ? "还没有选择文件夹" : state.gameDir)
                    .font(.system(size: 11.5, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(state.gameDir.isEmpty ? .secondary : .primary)
                Spacer(minLength: 8)
                Button("重新读取") { state.refreshPlan() }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(state.gameDir.isEmpty)
                Button("选择…") { pickGameFolder() }
                    .buttonStyle(SecondaryButtonStyle())
            }

            VStack(spacing: 0) {
                DataRow(title: "游戏本体", detail: Plan.fileName(state.plan?.base ?? ""),
                        state: (state.plan?.base ?? "").isEmpty ? .idle : .ok)
                Divider().padding(.leading, 12)
                DataRow(title: "更新包", detail: (state.plan?.updates ?? []).map(Plan.fileName).joined(separator: ", "),
                        state: (state.plan?.updates ?? []).isEmpty ? .idle : .ok)
                Divider().padding(.leading, 12)
                DataRow(title: "追加内容", detail: (state.plan?.dlc ?? []).map(Plan.fileName).joined(separator: ", "),
                        state: (state.plan?.dlc ?? []).isEmpty ? .idle : .ok)
                Divider().padding(.leading, 12)
                DataRow(title: "移植档案", detail: state.plan?.hasPort == true ? "已就绪 · \(state.plan?.version ?? "")" : "没有移植档案",
                        state: state.plan?.hasPort == true ? .ok : .warn)
                Divider().padding(.leading, 12)
                DataRow(title: "着色器缓存", detail: state.plan?.built == true ? "已编译（可直接导出）" : "未编译（首次要 30–60 分钟）",
                        state: state.plan?.built == true ? .ok : .idle)
                Divider().padding(.leading, 12)
                HStack(spacing: 10) {
                    Image(systemName: "key")
                        .font(.system(size: 13))
                        .foregroundStyle(state.keysPath.isEmpty ? DS.idle : DS.ok)
                    Text("主机密钥").font(.system(size: 13))
                    Spacer(minLength: 12)
                    Text(state.keysPath.isEmpty ? "还没有选择" : (state.keysPath as NSString).lastPathComponent)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Button("选择…") { pickKeys() }
                        .buttonStyle(QuietButtonStyle())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: DS.small, style: .continuous))
            .frame(maxWidth: .infinity, alignment: .leading)

            if let notes = state.plan?.notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(notes, id: \.self) { n in
                        HStack(alignment: .top, spacing: 5) {
                            Text("·").foregroundStyle(DS.warn)
                            Text(n).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    // MARK: - the settings

    private var settings: some View {
        Card(title: "设置", systemImage: "slider.horizontal.3") {
            VStack(spacing: 0) {
                settingRow("目标帧率") {
                    Picker("", selection: $state.targetFPS) {
                        Text("60 帧").tag(60)
                        Text("30 帧（省电）").tag(30)
                    }
                    .labelsHidden()
                    .frame(width: 160)
                    .onChange(of: state.targetFPS) { _, _ in state.writeEnv() }
                }
                Divider().padding(.leading, 12)
                settingRow("导出目录") {
                    Text(state.exportDir)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Button("选择…") { pickExportDir() }.buttonStyle(QuietButtonStyle())
                }
                Divider().padding(.leading, 12)
                settingRow("工具目录") {
                    Text(state.home.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Button("重新读取") { state.refreshPlan() }.buttonStyle(QuietButtonStyle())
                }
            }
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: DS.small, style: .continuous))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func settingRow<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 13)).frame(width: 72, alignment: .leading)
            content()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - the action bar (always visible at the bottom)

    private var actionBar: some View {
        HStack(spacing: 10) {
            Text(actionHint)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Button {
                if state.plan?.built == true { state.launchGame() } else { state.startBuild() }
            } label: {
                Label(state.plan?.built == true ? "开始游戏" : "开始编译",
                      systemImage: state.plan?.built == true ? "play.fill" : "hammer.fill")
            }
            .buttonStyle(PrimaryButtonStyle(enabled: !state.busy))
            .frame(width: 148)
            .disabled(state.busy)

            Button { state.exportMacApp() } label: {
                Label("导出 .app", systemImage: "app.dashed")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(state.busy || state.plan?.built != true)

            Button { state.exportUnsignedIPA() } label: {
                Label("导出 IPA", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(state.busy || state.plan?.built != true)
        }
    }

    /// The one line on the left of the action bar: what the buttons will do.
    private var actionHint: String {
        if state.busy {
            return state.stageName.isEmpty ? "处理中，请勿关闭" : "\(state.stageName) · 请勿关闭"
        }
        guard let p = state.plan else { return "先选择一个游戏文件夹" }
        if !p.repoOK { return "找不到 nxnative 源码目录" }
        return p.built ? "已编译 · \(p.version) · 可以直接开始游戏" : "首次编译需要 30–60 分钟"
    }

    // MARK: - the log

    private var log: some View {
        Card(title: "日志", systemImage: "text.alignleft") {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(state.logLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(line.hasPrefix("✗") ? DS.bad : .secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if state.logLines.isEmpty {
                        Text("还没有输出。").font(.system(size: 10.5)).foregroundStyle(.tertiary)
                    }
                }
                .padding(8)
            }
            .frame(minHeight: 64, maxHeight: 140)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: DS.small, style: .continuous))
        }
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
