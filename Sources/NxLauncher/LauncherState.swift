// The launcher's state: the plan, the settings, and the run of the pipeline.
import Foundation
import SwiftUI

@MainActor
final class LauncherState: ObservableObject {
    // --- what the user picked ---
    @Published var gameDir: String = ""
    @Published var keysPath: String = ""
    @Published var exportDir: String = (NSHomeDirectory() as NSString).appendingPathComponent("Desktop")
    @Published var targetFPS: Int = 60
    @Published var language: Language = .system

    // --- what the pipeline found ---
    @Published var plan: Plan?
    @Published var games: [GamesEntry] = []

    // --- the run ---
    @Published var busy: Bool = false
    @Published var stageName: String = ""
    @Published var stepName: String = ""
    @Published var fraction: Double? = nil
    @Published var progressNote: String = ""
    @Published var statusText: String = "就绪"
    @Published var logLines: [String] = []

    enum Language: String, CaseIterable, Identifiable {
        case system = "跟随系统"
        case zhHans = "简体中文"
        case enUS = "English"
        var id: String { rawValue }
        var code: String? {
            switch self {
            case .system: return nil
            case .zhHans: return "zh-Hans"
            case .enUS: return "en-US"
            }
        }
    }

    // --- where the tools are ---
    /// The repository root (the one with Tools/pack_pipeline.py): the environment, the app bundle's
    /// resources, or the source tree this binary was built from.
    let home: URL

    init() {
        home = LauncherState.findHome()
        // The window can be opened on a game folder from the command line:
        //   NxLauncher --game-dir ~/Games/BotW --keys ~/keys/prod.keys
        let args = CommandLine.arguments
        var i = 1
        while i < args.count - 1 {
            switch args[i] {
            case "--game-dir": gameDir = args[i + 1]; i += 2
            case "--keys": keysPath = args[i + 1]; i += 2
            case "--export-dir": exportDir = args[i + 1]; i += 2
            default: i += 1
            }
        }
    }

    static func findHome() -> URL {
        let fm = FileManager.default
        if let e = ProcessInfo.processInfo.environment["NXLAUNCHER_HOME"], fm.fileExists(atPath: e) {
            return URL(fileURLWithPath: e)
        }
        // the .app bundle: Contents/Resources/nxlauncher-home.txt says where the repository is
        let exe = URL(fileURLWithPath: CommandLine.arguments.first ?? "").deletingLastPathComponent()
        let resources = exe.deletingLastPathComponent().appendingPathComponent("Resources")
        let pointer = resources.appendingPathComponent("nxlauncher-home.txt")
        if let text = try? String(contentsOf: pointer, encoding: .utf8) {
            let dir = URL(fileURLWithPath: text.trimmingCharacters(in: .whitespacesAndNewlines))
            if fm.fileExists(atPath: dir.appendingPathComponent("Tools/pack_pipeline.py").path) { return dir }
        }
        // the source tree this binary was built from
        for dir in [exe, exe.deletingLastPathComponent(), exe.deletingLastPathComponent().deletingLastPathComponent()] {
            if fm.fileExists(atPath: dir.appendingPathComponent("Tools/pack_pipeline.py").path) { return dir }
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    var toolsDir: URL { home.appendingPathComponent("Tools") }
    var pipeline: Pipeline { Pipeline(toolsDir: toolsDir) }

    // --- the plan ---

    func refreshPlan() {
        guard !gameDir.isEmpty else { plan = nil; return }
        var args = ["plan", "--game-dir", gameDir]
        if !keysPath.isEmpty { args += ["--keys", keysPath] }
        do {
            try pipeline.run(args) { [weak self] event in
                DispatchQueue.main.async { self?.handle(event) }
            }
        } catch {
            statusText = "读取游戏文件夹失败：\(error.localizedDescription)"
        }
    }

    func loadGames() {
        do {
            try pipeline.run(["games"]) { [weak self] event in
                DispatchQueue.main.async { self?.handle(event) }
            }
        } catch {
            statusText = "读取游戏列表失败：\(error.localizedDescription)"
        }
    }

    private func handle(_ event: PipelineEvent) {
        switch event {
        case .plan(let p):
            plan = p
            statusText = p.built ? "已就绪" : "尚未编译"
        case .games(let g):
            games = g
        case .stage(let name, let step):
            stageName = name
            stepName = step
            fraction = nil
        case .progress(_, let step, _, _, let frac, let note):
            if !step.isEmpty { stepName = step }
            fraction = frac
            progressNote = note
        case .stageEnd(let name, let ok, let summary):
            stageName = ""
            stepName = ""
            fraction = nil
            if !summary.isEmpty { appendLog((ok ? "✓ " : "✗ ") + name + ": " + summary) }
        case .say(let msg):
            appendLog(msg)
        case .log(let line):
            appendLog(line)
        case .error(let msg):
            appendLog("错误：" + msg)
            statusText = msg
        }
    }

    private func appendLog(_ line: String) {
        logLines.append(line)
        if logLines.count > 500 { logLines.removeFirst(logLines.count - 500) }
    }

    // --- the runs ---

    func startBuild() {
        guard !gameDir.isEmpty, !keysPath.isEmpty else {
            statusText = "先选游戏文件夹和主机密钥"
            return
        }
        // the values the background work needs are read here, on the main actor: the background
        // closure must not touch the state (it would be a data race)
        let dir = gameDir, keys = keysPath, pipeline = self.pipeline
        busy = true
        statusText = "编译中"
        logLines.removeAll()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try pipeline.run(["build", "--game-dir", dir, "--keys", keys]) { event in
                    Task { @MainActor in self?.handle(event) }
                }
                Task { @MainActor in
                    self?.statusText = "编译完成"
                    self?.busy = false
                    self?.refreshPlan()
                }
            } catch {
                Task { @MainActor in
                    self?.appendLog("编译失败：\(error.localizedDescription)")
                    self?.statusText = "编译失败"
                    self?.busy = false
                }
            }
        }
    }

    func exportMacApp() {
        guard let plan, plan.built else { statusText = "还没有编译，先编译一次"; return }
        let out = URL(fileURLWithPath: exportDir).appendingPathComponent("\(supportName).app").path
        let extra = ["--game", plan.baseTitleID, "--ver", plan.version,
                     "--work", plan.workDir, "--name", supportName,
                     "--display", plan.name,
                     "--dlc", dlcDir()].filter { !$0.isEmpty }
        runExport(target: "mac-app", out: out, extra: extra)
    }

    func exportUnsignedIPA() {
        guard let plan, plan.built else { statusText = "还没有编译，先编译一次"; return }
        let out = URL(fileURLWithPath: exportDir).appendingPathComponent("\(plan.name).ipa").path
        runExport(target: "ios-ipa-unsigned", out: out, extra: ["--work", plan.workDir])
    }

    private func runExport(target: String, out: String, extra: [String]) {
        let pipeline = self.pipeline
        busy = true
        statusText = "导出中"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try pipeline.run(["export", "--target", target, "--out", out] + extra) { event in
                    Task { @MainActor in self?.handle(event) }
                }
                Task { @MainActor in
                    self?.statusText = "导出完成：\(out)"
                    self?.busy = false
                }
            } catch {
                Task { @MainActor in
                    self?.appendLog("导出失败：\(error.localizedDescription)")
                    self?.statusText = "导出失败"
                    self?.busy = false
                }
            }
        }
    }

    /// Start the built Mac .app (it is a normal macOS app: NSWorkspace opens it).
    func launchGame() {
        guard let plan, plan.built else { statusText = "还没有编译，先编译一次"; return }
        let app = URL(fileURLWithPath: exportDir).appendingPathComponent("\(supportName).app")
        if !FileManager.default.fileExists(atPath: app.path) {
            statusText = "先导出 .app（导出目录里没有）"
            return
        }
        NSWorkspace.shared.open(app)
        statusText = "已启动"
    }

    // --- the settings the game reads ---

    /// The Application Support folder the Mac app uses (saves, log.txt, env.txt).
    var supportDir: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent(supportName)
    }

    var supportName: String {
        if let n = plan?.name, !n.isEmpty { return n }
        return "nxnative"
    }

    /// The add-on content folder, when the work folder has one.
    private func dlcDir() -> String {
        guard let plan, !plan.workDir.isEmpty else { return "" }
        let aoc = URL(fileURLWithPath: plan.workDir).appendingPathComponent("aoc")
        return FileManager.default.fileExists(atPath: aoc.path) ? aoc.path : ""
    }

    /// Write the settings the game reads (env.txt in the support folder).
    ///
    /// The lines the launcher owns (the frame rate, the language) are rewritten; every other
    /// line is kept. Overwriting the whole file would silently drop what the user added by
    /// hand (DM_PADMAP, DM_AUDIO, ...).
    func writeEnv() {
        let dir = supportDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("env.txt")
        var kept: [String] = []
        var hasAudio = false
        if let data = try? Data(contentsOf: file), let old = String(data: data, encoding: .utf8) {
            for raw in old.split(separator: "\n", omittingEmptySubsequences: false) {
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.isEmpty || line.hasPrefix("#") { continue }
                let key = line.split(separator: "=", maxSplits: 1).first.map(String.init) ?? ""
                if key == "DM_FPS_TARGET" || key == "DM_LANG" { continue }   // the launcher writes these
                if key == "DM_AUDIO" { hasAudio = true }
                kept.append(line)
            }
        }
        var lines: [String] = ["# written by NxLauncher"]
        lines.append("DM_FPS_TARGET=\(targetFPS)")
        if let code = language.code { lines.append("DM_LANG=\(code)") }
        // The sound: the Mac host is silent unless DM_AUDIO=1 (on iOS it is on by default).
        // Only added when the user has not set it themselves.
        if !hasAudio { lines.append("DM_AUDIO=1") }
        lines.append(contentsOf: kept)
        let text = lines.joined(separator: "\n") + "\n"
        try? text.write(to: file, atomically: true, encoding: .utf8)
        statusText = "设置已写入 \(file.path)"
    }
}
