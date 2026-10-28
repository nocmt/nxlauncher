// The window: the game folder and what is in it, the settings, and the buttons.
import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: LauncherState
    @State private var workspace = false
    @State private var showGeneralSettings = false
    @State private var showLog = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if workspace {
                    workspaceView
                } else {
                    GameLibraryView(openWorkspace: { workspace = true }, addGame: pickGameFolder,
                                    openSettings: { showGeneralSettings = true })
                }
            }
            .sheet(isPresented: $showGeneralSettings) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Text("通用设置").font(.system(size: 21, weight: .semibold))
                            Spacer()
                            Button("完成") { showGeneralSettings = false }.buttonStyle(QuietButtonStyle())
                        }
                        globalSettings
                        buildEnvironment
                        logActions
                    }.padding(24)
                }.frame(width: 640, height: 580)
            }
            .onAppear {
                state.loadEnv()          // what is really in effect, from env.txt
                // the app carries its own tools (in an archive): unpack them before anything runs
                state.prepare {
                    state.checkDependencies()
                    state.loadGames()
                    if !state.gameDir.isEmpty { state.refreshPlan() }
                }
            }

            // The toast: a message that floats over the window and disappears by itself. It sits in
            // the bottom right corner, so it never covers the control that was just used.
            if let text = state.toast {
                Toast(text: text,
                      systemImage: state.toastIsWarning ? "exclamationmark.triangle.fill"
                                                        : "checkmark.circle.fill",
                      color: state.toastIsWarning ? DS.warn : DS.ok)
                    .padding(.trailing, 18)
                    .padding(.bottom, 74)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if state.canOperate && !state.busy && !state.installingDependencies { state.checkDependencies() }
        }
        .preferredColorScheme(state.appearance.colorScheme)
        .animation(.easeOut(duration: 0.22), value: state.toast)
    }

    private var workspaceView: some View {
        VStack(spacing: 0) {
            HStack {
                Button { workspace = false } label: { Label("游戏库", systemImage: "chevron.left") }
                    .buttonStyle(QuietButtonStyle())
                Spacer()
                Text("游戏工作区").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            }.padding(.horizontal, 24).padding(.vertical, 12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if state.preparing || !state.preparationError.isEmpty {
                        HStack {
                            Text(state.preparing ? state.statusText : "工具准备失败：\(state.preparationError)").font(.system(size: 12)).foregroundStyle(DS.warn)
                            Spacer()
                            if !state.preparing { Button("重试准备") { state.retryPreparation() }.buttonStyle(QuietButtonStyle()) }
                        }
                    }
                    if !state.errorHint.isEmpty {
                        Text("建议：\(state.errorHint)").font(.system(size: 12)).foregroundStyle(DS.warn).textSelection(.enabled)
                    }
                    if state.busy { progressStrip }
                    gameData
                    settings
                    logSection
                }
                .padding(24)
                .frame(maxWidth: 1120, alignment: .leading).frame(maxWidth: .infinity)
            }
            Divider()
            actionBar.padding(.horizontal, 24).padding(.vertical, 12).background(.bar)
        }
        .background(LinearGradient(colors: [DS.windowTop, DS.windowBottom], startPoint: .top, endPoint: .bottom))
        .onChange(of: state.busy) { _, running in if running { showLog = true } }
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
        .background(DS.row, in: RoundedRectangle(cornerRadius: DS.small, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.small, style: .continuous)
                .strokeBorder(DS.hairline, lineWidth: 1)
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
            if let game = state.library.first(where: { $0.id == state.selectedGameID }) {
                Button { state.revealGameFolder(game) } label: { Label("显示文件夹", systemImage: "folder") }
                    .buttonStyle(QuietButtonStyle())
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }

    private var statusLine: String {
        if state.busy { return state.statusText }
        // A message from the last action (it failed, or it wrote the settings): it stays on the
        // screen, so nothing the user does ends in silence.
        if !state.notice.isEmpty { return state.notice }
        guard let p = state.plan else { return "还没有选择游戏文件夹" }
        if !p.repoOK { return "找不到 nxnative 源码目录" }
        if p.built { return "已就绪 · \(p.version)" }
        return "未编译"
    }

    private var statusColor: Color {
        if state.busy { return DS.warn }
        if !state.notice.isEmpty { return state.noticeIsError ? DS.bad : DS.ok }
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

    /// The base game, as a list (it is one file, but the row takes a list like the other groups).
    private var baseFiles: [GameFile] {
        guard let base = state.plan?.base else { return [] }
        return [base]
    }

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
                    .disabled(state.gameDir.isEmpty || state.busy)
                Button("更换…") { pickGameFolder() }
                    .buttonStyle(SecondaryButtonStyle()).disabled(state.busy)
            }

            VStack(spacing: 0) {
                FileGroupRow(title: "游戏本体", files: baseFiles,
                             state: baseFiles.isEmpty ? .idle : .ok)
                Divider().padding(.leading, 12)
                FileGroupRow(title: "更新包", files: state.plan?.updates ?? [],
                             state: (state.plan?.updates ?? []).isEmpty ? .idle : .ok)
                Divider().padding(.leading, 12)
                FileGroupRow(title: "追加内容", files: state.plan?.dlc ?? [],
                             state: (state.plan?.dlc ?? []).isEmpty ? .idle : .ok)
                Divider().padding(.leading, 12)
                DataRow(title: "移植档案", detail: state.plan?.hasPort == true ? "已就绪 · \(state.plan?.version ?? "")" : "没有移植档案",
                        state: state.plan?.hasPort == true ? .ok : .warn)
                Divider().padding(.leading, 12)
                DataRow(title: "着色器缓存", detail: state.plan?.built == true ? "已编译" : "未编译",
                        state: state.plan?.built == true ? .ok : .idle)
                .padding(.vertical, 8)
            }
            .background(DS.row, in: RoundedRectangle(cornerRadius: DS.small, style: .continuous))
            .frame(maxWidth: .infinity, alignment: .leading)

            if let plan = state.plan {
                Text("构建状态：\(plan.buildStatus ?? (plan.built ? "ready" : "missing")) · \(plan.graphicsAPI ?? "auto")")
                    .font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
                ForEach(plan.shaderWarnings ?? [], id: \.self) { warning in
                    Text("着色器警告：\(warning)").font(.system(size: 11)).foregroundStyle(DS.warn).textSelection(.enabled)
                }
            }
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
        Card(title: "游戏设置", systemImage: "slider.horizontal.3") {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) {
                    languageChoice
                    fpsChoice
                    modeChoice
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 24) { languageChoice; fpsChoice }
                    modeChoice
                }
                VStack(alignment: .leading, spacing: 14) { languageChoice; fpsChoice; modeChoice }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .disabled(state.busy)
            .background(DS.row, in: RoundedRectangle(cornerRadius: DS.small, style: .continuous))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var languageChoice: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("游戏语言").font(.system(size: 12, weight: .medium))
            SegmentedChoice(options: LauncherState.Language.allCases.map {
                SegmentedChoice<LauncherState.Language>.Option(value: $0, label: $0.rawValue)
            }, selection: $state.language, optionWidth: 84)
        }
        .onChange(of: state.language) { _, _ in state.runtimeSettingsChanged() }
    }

    private var fpsChoice: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("目标帧率").font(.system(size: 12, weight: .medium))
            SegmentedChoice(options: [.init(value: 60, label: "60 帧"), .init(value: 30, label: "30 帧")],
                            selection: $state.targetFPS, optionWidth: 92)
        }
        .onChange(of: state.targetFPS) { _, _ in state.runtimeSettingsChanged() }
    }

    private var modeChoice: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("运行模式").font(.system(size: 12, weight: .medium))
            SegmentedChoice(options: [
                .init(value: LauncherState.OpMode.handheld, label: "掌机 720p"),
                .init(value: LauncherState.OpMode.console, label: "主机 1080p"),
            ], selection: $state.opMode, optionWidth: 116)
        }
        .help(modeHint)
        .onChange(of: state.opMode) { _, _ in state.runtimeSettingsChanged() }
    }

    private var keysSetting: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: "key").foregroundStyle(state.keysPath.isEmpty ? DS.warn : DS.ok)
                Text("主机密钥").font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
                Button(state.keysPath.isEmpty ? "选择…" : "更换…", action: pickKeys)
                    .buttonStyle(QuietButtonStyle()).disabled(state.busy)
            }
            Text(state.keysPath.isEmpty ? "未选择 prod.keys" : state.keysPath)
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle).help(state.keysPath)
        }.padding(12)
    }

    private var globalSettings: some View {
        Card(title: "偏好设置", systemImage: "slider.horizontal.3") {
            keysSetting
            Divider()
            settingRow("外观") {
                Picker("", selection: $state.appearance) {
                    ForEach(LauncherState.Appearance.allCases) { a in Text(a.rawValue).tag(a) }
                }.labelsHidden().frame(width: 180)
                    .onChange(of: state.appearance) { _, _ in state.appearanceChanged() }
            }
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

    private var modeHint: String {
        switch state.opMode {
        case .handheld:
            return "1280×720，鼠标左键可确认。"
        case .console:
            return "1920×1080，使用键盘或手柄确认。"
        }
    }

    // MARK: - the build environment

    private var buildEnvironment: some View {
        Card(title: "编译环境", systemImage: "wrench.and.screwdriver") {
            HStack {
                Text("构建目标").font(.system(size: 12))
                Picker("构建目标", selection: $state.buildTarget) {
                    ForEach(LauncherState.BuildTarget.allCases) { target in Text(target.label).tag(target) }
                }.labelsHidden().pickerStyle(.segmented).frame(width: 160)
                    .disabled(state.busy || state.installingDependencies || state.checkingDependencies)
                    .onChange(of: state.buildTarget) { _, _ in state.buildTargetChanged() }
                Spacer()
            }
            HStack(spacing: 12) {
                Button("Xcode 官网") { state.openOfficialURL("https://developer.apple.com/xcode/") }
                Button("Apple 下载（Metal）") { state.openOfficialURL("https://developer.apple.com/download/all/") }
                Button("Homebrew 官网") { state.openOfficialURL("https://brew.sh/") }
                Button("Python 官网") { state.openOfficialURL("https://www.python.org/downloads/macos/") }
            }.buttonStyle(.link).font(.system(size: 10))
            if state.preparing { Text(state.statusText).font(.system(size: 12)).foregroundStyle(DS.warn) }
            if !state.preparationError.isEmpty {
                Text("准备失败：\(state.preparationError)").font(.system(size: 11)).foregroundStyle(DS.bad)
                Button("重试准备") { state.retryPreparation() }.buttonStyle(QuietButtonStyle())
            }
            if state.installingDependencies {
                HStack { ProgressView().controlSize(.small); Text("安装中，完整输出见下方日志…").font(.system(size: 12)) }
            }
            if state.checkingDependencies && state.dependencies == nil {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("检查中…")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            } else if let report = state.dependencies {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(report.ready ? "可开始编译" : "缺少必需依赖")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(report.ready ? DS.ok : DS.warn)
                        Spacer()
                        Button { state.checkDependencies() } label: {
                            Label("重新检查", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(QuietButtonStyle())
                    }
                    // The whole header toggles: the same large target as the build log.
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) { state.showDependencies.toggle() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .rotationEffect(.degrees(state.showDependencies ? 90 : 0))
                            Text("依赖详情（\(report.checks.filter { $0.ok }.count)/\(report.checks.count) 已就绪）")
                                .font(.system(size: 11.5, weight: .medium))
                            Spacer(minLength: 0)
                            Text(state.showDependencies ? "收起" : "展开")
                                .font(.system(size: 10.5)).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(RoundedRectangle(cornerRadius: DS.small, style: .continuous).fill(DS.quiet))
                    .accessibilityLabel(state.showDependencies ? "收起依赖详情" : "展开依赖详情")
                    if state.showDependencies {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(report.checks) { check in
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: check.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            .foregroundStyle(check.ok ? DS.ok : DS.bad).frame(width: 14)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(check.name).font(.system(size: 11, weight: .medium))
                                            Text(check.detail).font(.system(size: 10)).foregroundStyle(.secondary)
                                                .lineLimit(check.ok ? 2 : nil).textSelection(.enabled)
                                            if !check.ok {
                                                Text(check.hint).font(.system(size: 10)).foregroundStyle(DS.warn)
                                                    .textSelection(.enabled)
                                            }
                                        }
                                        Spacer(minLength: 0)
                                    }
                                }
                            }.padding(.vertical, 8)
                        }.frame(height: 240)
                    }
                    ForEach((report.repairs ?? []).filter { $0.approvedArguments != nil }) { repair in
                        Button { state.installDependency(repair) } label: {
                            Label("授权安装 \(repair.argv.dropFirst(2).joined(separator: " "))…", systemImage: "arrow.down.circle")
                        }.buttonStyle(QuietButtonStyle())
                            .disabled(state.busy || state.installingDependencies || state.checkingDependencies || !state.canOperate)
                    }
                    Text("安装需逐项确认。Xcode、Metal、Homebrew 与 Python 请按官网指引手动安装；返回应用后自动复检。")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    if !report.commands.isEmpty {
                        Text(report.commands.joined(separator: "\n"))
                            .font(.system(size: 10, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DS.row, in: RoundedRectangle(cornerRadius: 5))
                    }
                }
            } else if !state.dependencyError.isEmpty {
                Text(state.dependencyError).font(.system(size: 11)).foregroundStyle(DS.bad)
                Button("重新检查") { state.checkDependencies() }
                    .buttonStyle(QuietButtonStyle())
            } else {
                Text("尚未检查").font(.system(size: 11)).foregroundStyle(.secondary)
                Button("检查编译环境") { state.checkDependencies() }
                    .buttonStyle(QuietButtonStyle())
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Text(actionHint)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Button {
                if state.buildTarget == .mac && state.plan?.isBuilt(for: "mac") == true { state.launchGame() } else { state.startBuild() }
            } label: {
                Label(state.buildTarget == .mac && state.plan?.isBuilt(for: "mac") == true ? "开始游戏" : "开始编译",
                      systemImage: state.buildTarget == .mac && state.plan?.isBuilt(for: "mac") == true ? "play.fill" : "hammer.fill")
            }
            .buttonStyle(PrimaryButtonStyle(enabled: !state.busy))
            .frame(width: 148)
            .disabled(state.busy || !state.canOperate)
            Menu {
                Button("重新构建（保留提取结果与存档）") { state.startBuild(rebuild: true) }
                Button("重新构建着色器") { state.startBuild(shadersOnly: true) }
            } label: { Image(systemName: "arrow.clockwise") }
                .menuStyle(.borderlessButton).frame(width: 28)
                .disabled(state.busy || !state.canOperate || state.plan == nil)

            Button { state.exportMacApp() } label: {
                Label("导出 .app…", systemImage: "app.dashed")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(state.busy || !state.canOperate || state.plan?.isBuilt(for: "mac") != true)

            Button { state.exportUnsignedIPA() } label: {
                Label("导出 IPA…", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(state.busy || !state.canOperate || state.plan?.isBuilt(for: "ios") != true)
        }
    }

    /// The one line on the left of the action bar: what the buttons will do.
    private var actionHint: String {
        if state.busy {
            return state.stageName.isEmpty ? "处理中，请勿关闭" : "\(state.stageName) · 请勿关闭"
        }
        guard let p = state.plan else { return "先选择一个游戏文件夹" }
        if !p.repoOK { return "找不到 nxnative 源码目录" }
        return p.built ? "已编译 · \(p.version)" : "未编译"
    }

    // MARK: - the log

    /// The log header is one full-width button: clicking the title, the count or the chevron
    /// expands it, which is a much larger target than the disclosure triangle alone.
    private var logSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { showLog.toggle() }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(showLog ? 90 : 0))
                    Text("构建日志（\(state.logLines.count) 条）")
                        .font(.system(size: 12, weight: .medium))
                    Spacer(minLength: 0)
                    Text(showLog ? "收起" : "展开")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(RoundedRectangle(cornerRadius: DS.small, style: .continuous).fill(DS.quiet))
            .accessibilityLabel(showLog ? "收起构建日志" : "展开构建日志")
            if showLog { log }
        }
    }

    /// The settings sheet keeps the log actions but not the log text: reading a build log belongs
    /// in the workspace, next to the build it describes.
    private var logActions: some View {
        Card(title: "日志与诊断", systemImage: "doc.text.magnifyingglass") {
            Text("完整日志可能包含本机路径；仅保存在本地，不会自动上传。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("打开日志") { state.openLogs() }.buttonStyle(QuietButtonStyle())
                Button("保存诊断包…") { state.saveDiagnostics() }.buttonStyle(QuietButtonStyle())
                    .disabled(state.busy || !state.canOperate)
                Button { state.copyCompleteLog() } label: { Label("复制全部", systemImage: "doc.on.doc") }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(state.logURL == nil && state.logLines.isEmpty)
                Spacer(minLength: 0)
            }
            Text(state.logLines.isEmpty ? "暂无日志；检查环境和构建过程会记录在这里。"
                                        : "当前 \(state.logLines.count) 条日志；内容在工作区的“构建日志”区域查看。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private var log: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 10) {
                Text("完整日志可能包含本机路径；仅保存在本地，不会自动上传。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("打开日志") { state.openLogs() }.buttonStyle(QuietButtonStyle())
                Button("保存诊断包…") { state.saveDiagnostics() }.buttonStyle(QuietButtonStyle())
                    .disabled(state.busy || !state.canOperate)
                Button { state.copyCompleteLog() } label: { Label("复制全部", systemImage: "doc.on.doc") }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(state.logURL == nil && state.logLines.isEmpty)
            }
            BuildLogView(lines: state.logLines)
                .frame(height: 200)
                .background(DS.row)
                .clipShape(RoundedRectangle(cornerRadius: DS.small, style: .continuous))
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
            state.addGameFolder(url)
            workspace = true
        }
    }

    private func pickKeys() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        if panel.runModal() == .OK, let url = panel.url {
            state.setKeys(url)
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
