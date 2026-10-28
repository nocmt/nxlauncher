// The launcher's state: the plan, the settings, and the run of the pipeline.
import AppKit
import Foundation
import SwiftUI
import CryptoKit
import Darwin

@MainActor
final class LauncherState: ObservableObject {
    // --- what the user picked ---
    @Published var gameDir: String = ""
    @Published var library: [LibraryGame] = []
    @Published var selectedGameID: String?
    @Published var keysPath: String = ""
    @Published var exportDir: String = (NSHomeDirectory() as NSString).appendingPathComponent("Desktop")
    @Published var targetFPS: Int = 60
    @Published var language: Language = .system

    // --- what the pipeline found ---
    @Published var plan: Plan?
    @Published var games: [GamesEntry] = []
    @Published var dependencies: DependencyReport?
    @Published var checkingDependencies = false
    @Published var dependencyError = ""
    @Published var showDependencies = false
    @Published var buildTarget: BuildTarget = .mac
    @Published var preparing = false
    @Published var preparationError = ""
    @Published var installingDependencies = false
    @Published var backendLogPath = ""
    @Published var sessionID = ""
    @Published var lastErrorID = ""
    @Published var errorHint = ""
    private(set) var logURL: URL?
    enum BuildTarget: String, CaseIterable, Identifiable {
        case mac, ios
        var id: String { rawValue }
        var label: String { self == .mac ? "Mac" : "iOS" }
    }
    var preparationReady: Bool { preparationArchive == nil || prepared }
    var canOperate: Bool { preparationReady && !preparing && !installingDependencies }


    // --- the run ---
    @Published var busy: Bool = false
    @Published var stageName: String = ""
    @Published var stepName: String = ""
    @Published var fraction: Double? = nil
    @Published var progressNote: String = ""
    @Published var statusText: String = "就绪"
    @Published var logLines: [String] = []
    /// What just happened, for the user: it stays on the screen until the next action, so a
    /// failure is never silent (the progress text alone is only for the running operations).
    @Published var notice: String = ""
    @Published var noticeIsError: Bool = false
    /// The .app that "开始游戏" starts. Exports before the fixed per-game support home
    /// (nxnative/<title id>) kept the saves in a folder named after it; the migration moves
    /// that folder over on the first run.
    @Published var gameAppPath: String = ""

    /// The operation mode: the handheld (720p, the Switch's touch screen exists) or the console
    /// (1080p, no touch screen -- as on the Switch, where the console is hooked up to a television).
    ///
    /// The mode also decides what the mouse is: in handheld mode the mouse is the touch screen,
    /// and since a console game like BotW has no touch UI at all, the mouse's left button is the
    /// A button (the confirm button of the menus); in console mode there is no touch screen, so
    /// the mouse is only a finger and the menus have to be driven with the keyboard or a pad.
    enum OpMode: String, CaseIterable, Identifiable {
        case handheld = "掌机模式（720p）"
        case console = "主机模式（1080p）"
        var id: String { rawValue }
        /// The value of DM_OPMODE.
        var code: Int { self == .handheld ? 0 : 1 }
        /// Whether the mouse's left button is the confirm button (DM_MOUSE_PAD).
        var mouseConfirms: Bool { self == .handheld }
        /// The mode from the command line (--opmode handheld|console).
        init?(argument: String) {
            switch argument.lowercased() {
            case "handheld", "0", "掌机": self = .handheld
            case "console", "1", "主机": self = .console
            default: return nil
            }
        }
    }
    @Published var opMode: OpMode = .handheld
    /// The mode asked for on the command line (--opmode), if there was one.
    var opModeArg: String?
    /// A message that floats over the window for a few seconds.
    @Published var toast: String? = nil
    @Published var toastIsWarning: Bool = false
    private var toastToken = 0

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

    /// How the window looks: the system's, or always light, or always dark. The colours are
    /// dynamic (they are asked for when they are drawn), so this is all it takes.
    enum Appearance: String, CaseIterable, Identifiable {
        case system = "跟随系统"
        case light = "浅色"
        case dark = "深色"
        var id: String { rawValue }
        /// nil = follow the system.
        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
    }
    @Published var appearance: Appearance = Appearance(
        rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system

    // --- where the tools are ---
    /// The folder the pipeline runs in: the repository (when the launcher runs from the sources),
    /// or the copy the app unpacked from the archive it carries.
    let home: URL
    private let libraryStore: GameLibraryStore
    private let supportRoot: URL
    private let preparationArchive: URL?
    private let preparationCache: URL
    private var planRequest = 0

    init(defaults: UserDefaults = .standard, arguments: [String] = CommandLine.arguments,
         home: URL? = nil, supportRoot: URL? = nil,
         preparationArchive: URL? = LauncherState.bundledArchive(), preparationCache: URL = LauncherState.cacheDir) {
        self.preparationArchive = preparationArchive
        self.preparationCache = preparationCache
        self.home = home ?? LauncherState.findHome()
        self.libraryStore = GameLibraryStore(defaults: defaults)
        self.supportRoot = supportRoot ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support")
        library = libraryStore.load()
        keysPath = defaults.string(forKey: GameLibraryStore.keysKey) ?? ""
        if let saved = defaults.string(forKey: GameLibraryStore.selectionKey),
           let game = library.first(where: { $0.id == saved }) {
            selectedGameID = game.id
            gameDir = game.folder
            gameAppPath = game.appPath
        }
        // No game-directory discovery: only saved references or an explicit --game-dir.
        let args = arguments
        var i = 1
        while i < args.count {
            switch args[i] {
            case "--game-dir" where i + 1 < args.count:
                gameDir = LibraryGame.canonicalPath(args[i + 1])
                selectedGameID = nil
                gameAppPath = ""
                i += 2
            case "--keys" where i + 1 < args.count:
                setKeys(URL(fileURLWithPath: (args[i + 1] as NSString).expandingTildeInPath))
                i += 2
            case "--export-dir" where i + 1 < args.count: exportDir = args[i + 1]; i += 2
            case "--opmode" where i + 1 < args.count: opModeArg = args[i + 1]; i += 2
            case "--launch": launchOnly = true; i += 1
            default: i += 1
            }
        }
        loadEnv()
        let logs = self.supportRoot.appendingPathComponent("NxLauncher/Logs", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
            let file = logs.appendingPathComponent("launcher-\(UUID().uuidString).log")
            try Data().write(to: file)
            logURL = file
        } catch { notify("无法建立完整日志：\(error.localizedDescription)", isError: true) }
    }

    private var selectedGame: LibraryGame? {
        library.first { $0.id == selectedGameID && $0.folder == LibraryGame.canonicalPath(gameDir) }
    }

    private func persistLibrary() {
        libraryStore.save(library, selectedID: selectedGameID)
    }

    func addGameFolder(_ url: URL) {
        guard !busy else { return }
        let folder = LibraryGame.canonicalPath(url.path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            notify("请选择存在的游戏文件夹", isError: true)
            return
        }
        if !library.contains(where: { $0.id == folder }) {
            library.append(LibraryGame(folder: folder))
        }
        if let game = library.first(where: { $0.id == folder }) { selectGame(game) }
    }

    func selectGame(_ game: LibraryGame) {
        guard !busy, let entry = library.first(where: { $0.id == game.id }) else { return }
        if selectedGameID != entry.id || gameDir != entry.folder {
            activateGame(entry)
        } else {
            persistLibrary()
        }
        refreshPlan()
    }

    func toggleGameSelection(_ game: LibraryGame) {
        guard !busy, library.contains(where: { $0.id == game.id }) else { return }
        if selectedGameID == game.id {
            activateGame(nil)
        } else {
            selectGame(game)
        }
    }

    private func activateGame(_ game: LibraryGame?) {
        planRequest &+= 1
        selectedGameID = game?.id
        gameDir = game?.folder ?? ""
        gameAppPath = game?.appPath ?? ""
        plan = nil
        logLines.removeAll()
        stageName = ""
        stepName = ""
        fraction = nil
        progressNote = ""
        statusText = "就绪"
        notice = ""
        noticeIsError = false
        lastErrorID = ""
        errorHint = ""
        toastToken &+= 1
        toast = nil
        toastIsWarning = false
        loadEnv()
        persistLibrary()
    }

    /// Removes the saved reference only: no game, export, save or support files are deleted.
    func removeGame(_ game: LibraryGame) {
        guard !busy, library.contains(where: { $0.id == game.id }) else { return }
        library.removeAll { $0.id == game.id }
        if selectedGameID == game.id {
            activateGame(library.first)
            if selectedGameID != nil { refreshPlan() }
        } else { persistLibrary() }
    }

    func setKeys(_ url: URL) {
        guard !busy else { return }
        keysPath = url.standardizedFileURL.path
        libraryStore.defaults.set(keysPath, forKey: GameLibraryStore.keysKey)
    }

    func revealGameFolder(_ game: LibraryGame) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: game.folder)
    }

    nonisolated static func validTitleID(_ id: String) -> Bool {
        id.utf8.count == 16 && id.utf8.allSatisfy { (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }
    }

    func saveDirectory(for game: LibraryGame) -> URL? {
        guard Self.validTitleID(game.titleID) else { return nil }
        return supportRoot.appendingPathComponent("nxnative", isDirectory: true)
            .appendingPathComponent(game.titleID, isDirectory: true).appendingPathComponent("save", isDirectory: true)
    }

    func openSaveDirectory(_ game: LibraryGame) {
        guard let directory = saveDirectory(for: game) else {
            notifyError("尚无有效的 16 位十六进制 Title ID，无法打开存档目录")
            return
        }
        do {
            // This action never runs legacy migration or touches another game's save.
            let root = supportRoot.appendingPathComponent("nxnative", isDirectory: true).standardizedFileURL
            let resolved = directory.resolvingSymlinksInPath().standardizedFileURL.path
            let expected = root.resolvingSymlinksInPath().appendingPathComponent(game.titleID).appendingPathComponent("save").path
            guard resolved == expected else {
                throw NSError(domain: "NxLauncher", code: 1, userInfo: [NSLocalizedDescriptionKey: "存档目录符号链接偏离此游戏的固定目录"])
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard NSWorkspace.shared.open(directory) else { notifyError("Finder 无法打开存档目录"); return }
        } catch { notifyError("无法打开存档目录：\(error.localizedDescription)") }
    }

    /// Start the game from the command line, without the window.
    var launchOnly = false

    static func findHome() -> URL {
        let fm = FileManager.default
        if let e = ProcessInfo.processInfo.environment["NXLAUNCHER_HOME"], fm.fileExists(atPath: e) {
            return URL(fileURLWithPath: e)
        }
        // the .app bundle: Contents/Resources/nxlauncher-home.txt says where the repository is.
        // It is only there when the app was built here; on another machine the path does not
        // exist and the app falls back to the archive it carries.
        let resources = bundleResources()
        let pointer = resources.appendingPathComponent("nxlauncher-home.txt")
        if let text = try? String(contentsOf: pointer, encoding: .utf8) {
            let dir = URL(fileURLWithPath: text.trimmingCharacters(in: .whitespacesAndNewlines))
            if fm.fileExists(atPath: dir.appendingPathComponent("Tools/pack_pipeline.py").path) { return dir }
        }
        // the shared app: it carries the archive, which is unpacked into the cache
        if let archive = bundledArchive(), let digest = try? archiveDigest(archive) {
            return cacheDir.appendingPathComponent("homes/\(digest)")
        }
        // the source tree this binary was built from
        let exe = URL(fileURLWithPath: CommandLine.arguments.first ?? "").deletingLastPathComponent()
        for dir in [exe, exe.deletingLastPathComponent(), exe.deletingLastPathComponent().deletingLastPathComponent()] {
            if fm.fileExists(atPath: dir.appendingPathComponent("Tools/pack_pipeline.py").path) { return dir }
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    var toolsDir: URL { home.appendingPathComponent("Tools") }

    /// The environment the pipeline runs in: the tree it works in, and the Python it runs under.
    private var pipelineEnv: [String: String] {
        var e: [String: String] = [:]
        let fm = FileManager.default
        // the Python's packages (lz4, capstone, fontTools, Pillow), installed next to it
        let libs = home.appendingPathComponent("py-libs")
        if fm.fileExists(atPath: libs.path) { e["PYTHONPATH"] = libs.path }
        // the upstream tree (the build writes into it)
        let repo = home.appendingPathComponent("nxnative")
        if fm.fileExists(atPath: repo.path) { e["NXLAUNCHER_REPO"] = repo.path }
        if let python = bundledPython { e["NXLAUNCHER_PYTHON"] = python }
        return e
    }

    /// The Python the app carries, if it carries one (the shared app does; the sources do not).
    var bundledPython: String? {
        let p = home.appendingPathComponent("python/bin/python3")
        return FileManager.default.fileExists(atPath: p.path) ? p.path : nil
    }

    var pipeline: Pipeline { Pipeline(toolsDir: toolsDir, python: bundledPython, env: pipelineEnv) }

    // MARK: - the archive the app carries

    /// The archive in the app bundle: the tools, the upstream tree, the Python wheels and a
    /// standalone Python, in one file. It is what makes the app shareable as a single file.
    nonisolated static func bundledArchive() -> URL? {
        let resources = LauncherState.bundleResources()
        let archive = resources.appendingPathComponent("nxlauncher-home.tgz")
        return FileManager.default.fileExists(atPath: archive.path) ? archive : nil
    }

    /// The bundle's Resources folder (the launcher runs from inside an .app).
    nonisolated static func bundleResources() -> URL {
        let exe = URL(fileURLWithPath: CommandLine.arguments.first ?? "").deletingLastPathComponent()
        return exe.deletingLastPathComponent().appendingPathComponent("Resources")
    }

    /// The cache folder: the app unpacks its archive here. Not in the bundle: the bundle can be
    /// read-only (in /Applications) and the build writes into the tree.
    nonisolated static var cacheDir: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Caches/NxLauncher")
    }

    /// Unpack the archive and get the Python ready. It happens once: the stamp says whether the
    /// cache is already the archive's contents. It moves about 130 MB, so it runs off the main
    /// thread.
    nonisolated static func archiveDigest(_ archive: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: archive)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func unpackHome() throws {
        guard let archive = bundledArchive() else { return }
        _ = try unpackArchive(archive, cache: cacheDir)
    }

    /// Publish only a completely extracted, offline-installed and import-verified home.
    /// A process-wide filesystem lock also serializes concurrent app instances.
    nonisolated static func unpackArchive(_ archive: URL, cache: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
        let fd = Darwin.open(cache.appendingPathComponent("prepare.lock").path, O_CREAT | O_RDWR, mode_t(0o600))
        guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { Darwin.close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { flock(fd, LOCK_UN) }
        let digest = try archiveDigest(archive)
        let homes = cache.appendingPathComponent("homes", isDirectory: true)
        try fm.createDirectory(at: homes, withIntermediateDirectories: true)
        let destination = homes.appendingPathComponent(digest, isDirectory: true)
        if (try? String(contentsOf: destination.appendingPathComponent(".ready"), encoding: .utf8)) == digest {
            return destination
        }
        let staging = homes.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        // Reject traversal names before extracting the trusted bundled payload.
        let entries = try run("/usr/bin/tar", ["-tzf", archive.path]).split(separator: "\n")
        guard entries.allSatisfy({ !$0.hasPrefix("/") && !$0.split(separator: "/").contains("..") }) else {
            throw NSError(domain: "NxLauncher", code: 1, userInfo: [NSLocalizedDescriptionKey: "工具归档包含不安全路径"])
        }
        try run("/usr/bin/tar", ["-xzf", archive.path, "-C", staging.path])
        let python = staging.appendingPathComponent("python/bin/python3")
        guard fm.isExecutableFile(atPath: python.path),
              fm.fileExists(atPath: staging.appendingPathComponent("Tools/pack_pipeline.py").path) else {
            throw NSError(domain: "NxLauncher", code: 1, userInfo: [NSLocalizedDescriptionKey: "工具归档缺少 Python 或 pipeline"])
        }
        let libs = staging.appendingPathComponent("py-libs")
        var env = ProcessInfo.processInfo.environment
        env["PYTHONPATH"] = libs.path
        env["PYTHONNOUSERSITE"] = "1"
        let verify = "import lz4.block, capstone, fontTools, PIL; import importlib.util; importlib.import_module('compression.zstd' if importlib.util.find_spec('compression') else 'backports.zstd')"
        if (try? run(python.path, ["-c", verify], env: env)) == nil {
            try fm.createDirectory(at: libs, withIntermediateDirectories: true)
            try run(python.path, ["-m", "pip", "install", "--no-index", "--disable-pip-version-check",
                                  "--find-links", staging.appendingPathComponent("wheels").path,
                                  "--target", libs.path, "--upgrade", "--force-reinstall",
                                  "lz4", "capstone", "fonttools", "pillow", "backports.zstd"], env: env)
        }
        try run(python.path, ["-c", verify], env: env)
        try digest.write(to: staging.appendingPathComponent(".ready"), atomically: true, encoding: .utf8)
        // Never delete the previous cache/home. An incomplete colliding destination is retained.
        if fm.fileExists(atPath: destination.path) {
            try fm.moveItem(at: destination, to: homes.appendingPathComponent("\(digest)-incomplete-\(UUID().uuidString)"))
        }
        try fm.moveItem(at: staging, to: destination)
        return destination
    }

    func prepare(_ done: @escaping () -> Void) {
        guard !preparing else { return }
        guard let archive = preparationArchive, !prepared else { done(); return }
        let cache = preparationCache
        preparing = true
        preparationError = ""
        statusText = "准备中（校验与解包工具）"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var failure = ""
            do { _ = try LauncherState.unpackArchive(archive, cache: cache) } catch { failure = error.localizedDescription }
            Task { @MainActor in
                guard let self else { return }
                self.preparing = false
                guard failure.isEmpty else {
                    self.preparationError = failure
                    self.statusText = "准备失败，可重试"
                    self.notify("准备失败：\(failure)", isError: true)
                    return // no doctor / plan / games / build after a failed preparation
                }
                self.prepared = true
                self.statusText = "就绪"
                done()
            }
        }
    }

    func retryPreparation() {
        prepare {
            self.checkDependencies()
            self.loadGames()
            if !self.gameDir.isEmpty { self.refreshPlan() }
        }
    }

    private var prepared = false

    /// Runs a tool and waits for it; it throws when the tool fails.
    @discardableResult
    nonisolated static func run(_ tool: String, _ args: [String], env: [String: String]? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        if let env { process.environment = env }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch {
            throw error
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            throw NSError(domain: "NxLauncher", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "\(URL(fileURLWithPath: tool).lastPathComponent) failed: \(text)"
            ])
        }
        return text
    }

    // --- the plan ---

    func refreshPlan() { refreshPlan(deliverImmediately: false) }

    private func refreshPlan(deliverImmediately: Bool) {
        guard !busy, canOperate else { return }
        let folder = LibraryGame.canonicalPath(gameDir)
        guard !folder.isEmpty else { planRequest &+= 1; plan = nil; return }
        // An explicit command-line folder (or legacy UI assignment) becomes a reference here.
        if selectedGame?.id != folder {
            if !library.contains(where: { $0.id == folder }) {
                library.append(LibraryGame(folder: folder))
            }
            activateGame(library.first { $0.id == folder })
        }
        planRequest &+= 1
        let request = planRequest
        plan = nil
        statusText = "读取游戏文件夹中"
        var args = ["plan", "--game-dir", folder, "--target", buildTarget.rawValue]
        if !keysPath.isEmpty { args += ["--keys", keysPath] }
        var immediateEvents: [PipelineEvent] = []
        do {
            try pipeline.run(args) { [weak self] event in
                if deliverImmediately { immediateEvents.append(event) }
                else {
                    DispatchQueue.main.async {
                        self?.handlePlanEvent(event, folder: folder, request: request)
                    }
                }
            }
            for event in immediateEvents { handlePlanEvent(event, folder: folder, request: request) }
        } catch {
            for event in immediateEvents { handlePlanEvent(event, folder: folder, request: request) }
            guard selectedGameID == folder, gameDir == folder, planRequest == request else { return }
            if let index = library.firstIndex(where: { $0.id == folder }) {
                library[index].built = false
                persistLibrary()
            }
            statusText = "读取游戏文件夹失败：\(error.localizedDescription)"
        }
    }

    private func handlePlanEvent(_ event: PipelineEvent, folder: String, request: Int) {
        guard !busy, selectedGameID == folder, gameDir == folder, planRequest == request else { return }
        if case .plan(let value) = event, !value.gameDir.isEmpty,
           LibraryGame.canonicalPath(value.gameDir) != folder { return }
        if case .session(let id, let path) = event, !sessionID.isEmpty {
            appendLog("读取计划会话 \(id) · Python 日志：\(path)")
            return // retain the build/export session as the diagnostic selection
        }
        handle(event)
    }

    func loadGames() {
        guard canOperate else { return }
        do {
            try pipeline.run(["games"]) { [weak self] event in
                DispatchQueue.main.async { self?.handle(event) }
            }
        } catch {
            statusText = "读取游戏列表失败：\(error.localizedDescription)"
        }
    }

    func checkDependencies() {
        guard !checkingDependencies, canOperate, !busy else { return }
        checkingDependencies = true
        dependencies = nil
        dependencyError = ""
        let pipeline = self.pipeline
        let target = buildTarget
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var report: DependencyReport?
            var failure = ""
            do {
                try pipeline.run(["doctor", "--target", target.rawValue]) { event in
                    if case .dependencies(let value) = event {
                        report = value
                    } else if case .error(let message) = event {
                        failure = message
                    }
                }
                if report == nil && failure.isEmpty { failure = "依赖检查未返回结果，请重试。" }
            } catch {
                failure = "依赖检查失败：\(error.localizedDescription)"
            }
            Task { @MainActor in
                guard self?.buildTarget == target else { self?.checkingDependencies = false; self?.checkDependencies(); return }
                self?.dependencies = failure.isEmpty ? report : nil
                self?.dependencyError = failure
                // Auto-open only when something is wrong. A finished check must never collapse a
                // section the user just opened.
                if report?.ready == false { self?.showDependencies = true }
                self?.checkingDependencies = false
            }
        }
    }

    func buildTargetChanged() {
        guard !busy, !installingDependencies else { return }
        dependencies = nil
        planRequest &+= 1
        checkDependencies()
        refreshPlan()
    }

    func installDependency(_ repair: DependencyRepair) {
        guard canOperate, !busy, !checkingDependencies, let args = repair.approvedArguments else { return }
        guard let brew = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            notify("未找到 Homebrew，请先从官网手动安装；不会自动安装 Homebrew", isError: true)
            return
        }
        let alert = NSAlert()
        alert.messageText = "授权安装 Homebrew 工具？"
        alert.informativeText = "将运行：\(brew) \(args.joined(separator: " "))\n安装会访问网络并写入 Homebrew。不会安装 Xcode 或 Homebrew。完整输出可在构建日志查看。"
        alert.addButton(withTitle: "确认安装")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        installingDependencies = true
        statusText = "安装依赖中"
        appendLog("用户授权：\(brew) \(args.joined(separator: " "))")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var failure: Error?
            do {
                try Pipeline.runTool(brew, args: args) { line in
                    DispatchQueue.main.async { self?.appendLog(line) }
                }
            } catch { failure = error }
            DispatchQueue.main.async {
                guard let self else { return }
                self.installingDependencies = false
                if let failure { self.notify("依赖安装失败：\(failure.localizedDescription)", isError: true) }
                else { self.notify("依赖安装完成，正在重新检查") }
                self.checkDependencies()
            }
        }
    }

    func openOfficialURL(_ address: String) {
        let allowed = ["https://developer.apple.com/xcode/", "https://developer.apple.com/download/all/", "https://brew.sh/", "https://www.python.org/downloads/macos/"]
        guard allowed.contains(address), let url = URL(string: address) else { return }
        if !NSWorkspace.shared.open(url) { notify("无法打开官方下载安装页面", isError: true) }
    }

    var completeLog: String {
        var parts: [String] = []
        if let logURL, let text = try? String(contentsOf: logURL, encoding: .utf8) { parts.append(text) }
        if !backendLogPath.isEmpty, let text = try? String(contentsOfFile: backendLogPath, encoding: .utf8) {
            parts.append("--- Python 完整日志 ---\n" + text)
        }
        return parts.isEmpty ? logLines.joined(separator: "\n") : parts.joined(separator: "\n")
    }

    func copyCompleteLog() {
        NSPasteboard.general.clearContents()
        if !NSPasteboard.general.setString(completeLog, forType: .string) { notify("复制日志失败", isError: true) }
    }

    func openLogs() {
        guard let logURL else { notify("日志尚不可用", isError: true); return }
        if !NSWorkspace.shared.open(logURL.deletingLastPathComponent()) { notify("无法打开日志目录", isError: true) }
    }

    func saveDiagnostics() {
        guard !busy, canOperate else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "NxLauncher-diagnostics.zip"
        panel.message = "保存脱敏诊断包（不含密钥内容、游戏或存档）"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var args = ["diagnostics", "--out", url.path]
        if !sessionID.isEmpty { args += ["--session", sessionID] }
        if let logURL { args += ["--launcher-log", logURL.path] }
        let pipeline = self.pipeline
        busy = true
        statusText = "保存诊断包中"
        lastErrorID = ""
        errorHint = ""
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var failure: Error?
            do {
                try pipeline.run(args) { event in DispatchQueue.main.async { self?.handle(event) } }
            } catch { failure = error }
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                if let failure { self.recordPipelineFailure(failure, operation: "保存诊断包") }
                else { self.notify("脱敏诊断包已保存：\(url.path)") }
            }
        }
    }

    func handle(_ event: PipelineEvent) {
        switch event {
        case .plan(let p):
            guard let game = selectedGame,
                  p.gameDir.isEmpty || LibraryGame.canonicalPath(p.gameDir) == game.id else { return }
            plan = p
            if !p.ok {
                if let index = library.firstIndex(where: { $0.id == game.id }) {
                    library[index].built = false
                    persistLibrary()
                }
                statusText = p.error ?? "读取游戏文件夹失败"
                return
            }
            statusText = p.base == nil ? "未找到基础游戏文件" : p.built ? "已就绪" : "尚未编译"
            if let index = library.firstIndex(where: { $0.id == game.id }) {
                if !p.name.isEmpty { library[index].name = p.name }
                library[index].icon = p.icon
                library[index].version = p.version
                library[index].titleID = p.baseTitleID
                library[index].built = p.isBuilt(for: "mac")
            }
            migrateLegacyGameApp()
            if let app = findGameApp() { setGameApp(app) }
            else { gameAppPath = selectedGame?.appPath ?? "" }
            migrateLegacySupportFolder()
            persistLibrary()
            loadEnv()
        case .games(let g):
            games = g
        case .dependencies(let report):
            dependencies = report
            dependencyError = ""
            if !report.ready { showDependencies = true }
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
            appendLog("✗ \(msg)")
        case .diagnostic(let id, let message, let hint, let session):
            lastErrorID = id
            errorHint = hint
            if !session.isEmpty { sessionID = session }
            appendLog("✗ [\(id)] \(message)" + (hint.isEmpty ? "" : "\n建议：\(hint)"))
            notice = id.isEmpty ? message : "\(message) [\(id)]"
            noticeIsError = true
        case .session(let id, let path):
            sessionID = id
            backendLogPath = path
            appendLog("会话 \(id) · Python 日志：\(path)")
        case .artifact(let target, let path, let game, _, _):
            appendLog("已导出 \(target)：\(path)")
            if ["mac", "mac-app"].contains(target),
               game == plan?.baseTitleID || game == selectedGame?.titleID,
               let app = existingApp(path) { setGameApp(app) }
        case .warning(let message):
            appendLog("警告：\(message)")
            showToast(message, warning: true)

        }
    }

    /// Record a process failure without repeating streamed diagnostics in the header or log.
    func recordPipelineFailure(_ error: Error, operation: String) {
        if let failure = error as? Pipeline.Failure {
            if case .cannotRun = failure, let diagnostic = failure.diagnostic {
                appendLog("✗ \(diagnostic)")
            }
            notice = failure.notice(operation: operation)
        } else {
            appendLog("✗ \(error.localizedDescription)")
            notice = "\(operation)失败，详情见构建日志"
        }
        if !lastErrorID.isEmpty { notice += " [\(lastErrorID)]" }
        noticeIsError = true
    }

    private func appendLog(_ line: String) {
        if let logURL {
            do {
                let handle = try FileHandle(forWritingTo: logURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data((line + "\n").utf8))
            } catch {
                notice = "完整日志写入失败：\(error.localizedDescription)"
                noticeIsError = true
            }
        }
        logLines.append(line)
        if logLines.count > 500 { logLines.removeFirst(logLines.count - 500) }
    }

    /// Say something to the user: it goes to the status line (it stays there until the next
    /// action) and to the log.
    func notify(_ message: String, isError: Bool = false) {
        notice = message
        noticeIsError = isError
        appendLog(isError ? "✗ " + message : message)
    }

    /// The appearance was changed in the window: remember it for the next time.
    func appearanceChanged() {
        UserDefaults.standard.set(appearance.rawValue, forKey: "appearance")
    }

    // --- the runs ---

    func startBuild(rebuild: Bool = false, shadersOnly: Bool = false) {
        guard !busy, canOperate, selectedGame != nil else { return }
        guard !checkingDependencies else {
            notify("正在检查编译环境，请稍候", isError: true)
            return
        }
        if let dependencies, !dependencies.ready {
            showDependencies = true
            notify("缺少编译依赖，请在游戏库的「通用设置」中查看", isError: true)
            return
        }
        guard !gameDir.isEmpty, !keysPath.isEmpty else {
            notify(gameDir.isEmpty ? "请先选择游戏文件夹" : "请在游戏库的「通用设置」中选择 prod.keys", isError: true)
            return
        }
        // the values the background work needs are read here, on the main actor: the background
        // closure must not touch the state (it would be a data race)
        let dir = gameDir, keys = keysPath, pipeline = self.pipeline
        var args = ["build", "--game-dir", dir, "--keys", keys, "--target", buildTarget.rawValue]
        if rebuild { args.append("--rebuild") }
        if shadersOnly { args.append("--rebuild-shaders") }
        let sourceID = selectedGameID
        planRequest &+= 1
        busy = true
        lastErrorID = ""
        errorHint = ""
        statusText = "编译中"
        notice = ""
        logLines.removeAll()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try pipeline.run(args) { event in
                    Task { @MainActor in
                        guard let self, self.selectedGameID == sourceID, self.gameDir == dir else { return }
                        self.handle(event)
                    }
                }
                Task { @MainActor in
                    guard let self, self.selectedGameID == sourceID, self.gameDir == dir else { return }
                    self.notify("编译完成（不会自动运行游戏）")
                    self.busy = false
                    self.refreshPlan()
                }
            } catch {
                Task { @MainActor in
                    guard let self, self.selectedGameID == sourceID, self.gameDir == dir else { return }
                    self.recordPipelineFailure(error, operation: "编译")
                    self.busy = false
                }
            }
        }
    }

    func exportMacApp() {
        guard !busy, canOperate, selectedGame != nil else { return }
        guard let plan, plan.isBuilt(for: "mac") else { notify("还没有 Mac 编译结果，先编译一次", isError: true); return }
        // the export is written from the work folder, so it is a new copy every time: ask where
        // it should go instead of keeping a directory in the settings
        guard let dir = askWhereToExport("把 .app 导出到这个文件夹") else { return }
        let out = URL(fileURLWithPath: dir).appendingPathComponent("\(supportName).app").path
        var extra = ["--game", plan.baseTitleID, "--ver", plan.version,
                     "--work", plan.workDir, "--name", supportName,
                     "--display", plan.name]
        let dlc = dlcDir()
        if !dlc.isEmpty { extra += ["--dlc", dlc] }
        runExport(target: "mac-app", out: out, extra: extra)
    }

    func exportUnsignedIPA() {
        guard !busy, canOperate, selectedGame != nil else { return }
        guard let plan, plan.isBuilt(for: "ios") else { notify("还没有 iOS 编译结果，请切换到 iOS 目标编译", isError: true); return }
        guard let dir = askWhereToExport("把 IPA 导出到这个文件夹") else { return }
        let out = URL(fileURLWithPath: dir).appendingPathComponent("\(plan.name).ipa").path
        runExport(target: "ios-ipa-unsigned", out: out,
                  extra: ["--game", plan.baseTitleID, "--ver", plan.version, "--work", plan.workDir])
    }

    /// Ask where to put the export (a folder chooser; the last one is the starting point).
    private func askWhereToExport(_ message: String) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "导出到这里"
        panel.message = message
        panel.directoryURL = URL(fileURLWithPath: exportDir)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        exportDir = url.path
        return url.path
    }

    private func runExport(target: String, out: String, extra: [String]) {
        guard !busy, canOperate, let sourceID = selectedGameID, selectedGame != nil else { return }
        let sourceFolder = gameDir
        let pipeline = self.pipeline
        planRequest &+= 1
        busy = true
        statusText = "导出中"
        lastErrorID = ""
        errorHint = ""
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try pipeline.run(["export", "--target", target, "--out", out, "--require-manifest"] + extra) { event in
                    Task { @MainActor in
                        guard let self, self.selectedGameID == sourceID, self.gameDir == sourceFolder else { return }
                        self.handle(event)
                    }
                }
                Task { @MainActor in
                    guard let self, self.selectedGameID == sourceID, self.gameDir == sourceFolder else { return }
                    // Associate the exported app only with the captured source game.
                    if target == "mac-app" { self.setGameApp(URL(fileURLWithPath: out)) }
                    self.notify("导出完成：\(out)")
                    self.busy = false
                }
            } catch {
                Task { @MainActor in
                    guard let self, self.selectedGameID == sourceID, self.gameDir == sourceFolder else { return }
                    self.recordPipelineFailure(error, operation: "导出")
                    self.busy = false
                }
            }
        }
    }

    /// The failure of an action whose button also exists outside the workspace (开始游戏 in the
    /// library): the notice stays in the log and the header, and the toast carries it over the
    /// window, so the failure is never something only the log has seen.
    private func notifyError(_ message: String) {
        notify(message, isError: true)
        showToast(message, warning: true)
    }

    /// Start the built Mac .app (it is a normal macOS app: NSWorkspace opens it).
    ///
    /// The .app is looked for in a few places, because the export directory is not the only one:
    /// the .app is usually built next to the game files. Whatever is found, the settings are
    /// written into that app's own support folder (the app's name is the folder's name), so the
    /// game really reads them.
    func launchGame() {
        guard !busy, canOperate, selectedGame != nil else { return }
        guard let plan, plan.isBuilt(for: "mac") else { notifyError("还没有 Mac 编译结果，先编译一次"); return }
        guard let app = findGameApp() else {
            notifyError("找不到已导出的 .app。导出目录：\(exportDir)；游戏文件夹：\(gameDir)。先点「导出 .app」，或把「导出目录」指到 .app 所在的文件夹。")
            return
        }
        setGameApp(app)
        migrateLegacySupportFolder()
        if appliedSettings?.supportPath != supportDir.path { loadEnv() }
        guard writeEnv() else { return }
        guard NSWorkspace.shared.open(app) else { notifyError("macOS 无法打开已导出的应用"); return }
        notify("已启动 \(app.lastPathComponent)")
    }

    /// A remembered per-game export may be renamed. Discovery only accepts the exact expected
    /// name: never enumerate arbitrary applications in a shared export folder.
    func findGameApp() -> URL? {
        guard let game = selectedGame else { return nil }
        if let remembered = existingApp(game.appPath) { return remembered }
        guard !supportName.isEmpty, supportName != "nxnative" else { return nil }
        for dir in appSearchDirectories {
            let named = URL(fileURLWithPath: dir).appendingPathComponent("\(supportName).app")
            if let app = existingApp(named.path) { return app }
        }
        return nil
    }

    private var appSearchDirectories: [String] {
        var dirs = [exportDir, gameDir]
        if let work = plan?.workDir, !work.isEmpty {
            dirs.append((work as NSString).deletingLastPathComponent)
        }
        return dirs.filter { !$0.isEmpty }
    }

    private func existingApp(_ path: String) -> URL? {
        guard !path.isEmpty else { return nil }
        let app = URL(fileURLWithPath: path).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard app.pathExtension.lowercased() == "app",
              FileManager.default.fileExists(atPath: app.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return app
    }

    private func migrateLegacyGameApp() {
        guard let game = selectedGame, game.appPath.isEmpty, let plan,
              !plan.name.isEmpty,
              let legacy = libraryStore.defaults.string(forKey: "gameAppPath"),
              let app = existingApp(legacy),
              app.lastPathComponent == "\(plan.name).app",
              appSearchDirectories.contains(where: {
                  LibraryGame.canonicalPath($0) == LibraryGame.canonicalPath(app.deletingLastPathComponent().path)
              }) else { return }
        // The exact expected application in a known location demonstrates the association.
        setGameApp(app)
        libraryStore.defaults.removeObject(forKey: "gameAppPath")
    }

    /// Remember this game's export only; a global last-app pointer is unsafe across games.
    private func setGameApp(_ app: URL) {
        guard let game = selectedGame,
              let index = library.firstIndex(where: { $0.id == game.id }) else { return }
        gameAppPath = app.standardizedFileURL.path
        library[index].appPath = gameAppPath
        persistLibrary()
    }

    /// Start the game from the command line, without the window:
    ///   NxLauncher --launch --game-dir ~/Games/BotW
    /// It prints where everything went, so a script (or a test) can see it.
    static func runLaunchFromCommandLine() {
        let state = LauncherState()
        state.refreshPlan(deliverImmediately: true)
        guard let app = state.findGameApp() else {
            print("no .app found (export dir: \(state.exportDir), game dir: \(state.gameDir))")
            return
        }
        state.setGameApp(app)
        guard state.writeEnv() else { print("settings write failed; not opening app"); return }
        print("app: \(app.path)")
        print("support: \(state.supportDir.path)")
        print("env: \(state.supportDir.appendingPathComponent("env.txt").path)")
        print("opened: \(NSWorkspace.shared.open(app))")
    }

    /// Put the operation mode into effect from the command line, without the window:
    ///   NxLauncher --opmode console
    /// It prints the mode, the message the user would see, and the env.txt that was written, so a
    /// script (or a test) can check it without clicking anything.
    static func runOpModeFromCommandLine() {
        let state = LauncherState()
        guard let raw = state.opModeArg, let mode = OpMode(argument: raw) else {
            print("usage: NxLauncher --opmode handheld|console")
            return
        }
        // the support folder depends on the .app that is started, so find it first
        state.refreshPlan(deliverImmediately: true)
        if let app = state.findGameApp() { state.setGameApp(app) }
        state.loadEnv()
        print("mode: \(mode.rawValue) (DM_OPMODE=\(mode.code), DM_MOUSE_PAD=\(mode.mouseConfirms ? 1 : 0))")
        print("message: \(state.setOpMode(mode))")
        let file = state.supportDir.appendingPathComponent("env.txt")
        print("env: \(file.path)")
        if let text = try? String(contentsOf: file, encoding: .utf8) {
            print("---")
            print(text.trimmingCharacters(in: .newlines))
        }
    }

    // --- the settings the game reads ---

    /// The Application Support folder the Mac app uses (saves, log.txt, env.txt): `nxnative/<title id>`
    /// — a fixed per-game home, so renaming the .app cannot lose the saves (the id is baked into the
    /// bundle; the folder name does not follow it). Exports from before that change keep their
    /// .app-name folder, and this follows them until the game is exported again.
    var supportDir: URL {
        let id = selectedGame?.titleID ?? plan?.baseTitleID ?? ""
        if Self.validTitleID(id), usesFixedSupportHome {
            return supportRoot.appendingPathComponent("nxnative", isDirectory: true)
                .appendingPathComponent(id, isDirectory: true)
        }
        return supportRoot.appendingPathComponent(appSupportName, isDirectory: true)
    }

    /// Whether the associated .app was built with the fixed per-game support home: its launcher
    /// carries the folder's name as a baked format string, so the bundle itself says which scheme
    /// it reads — no version file needed.
    private var usesFixedSupportHome: Bool {
        guard let game = selectedGame, Self.validTitleID(game.titleID), !game.appPath.isEmpty else { return false }
        let macOS = URL(fileURLWithPath: game.appPath, isDirectory: true).appendingPathComponent("Contents/MacOS")
        let marker = Data("Application Support/nxnative/\(game.titleID)".utf8)
        let files = (try? FileManager.default.contentsOfDirectory(at: macOS, includingPropertiesForKeys: [.isRegularFileKey]))?
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true } ?? []
        return files.contains { (try? Data(contentsOf: $0, options: .mappedIfSafe))?.range(of: marker) != nil }
    }

    /// Old exports kept the support folder under the .app's name, so renaming the .app started the
    /// game over without its saves. Move that folder into the fixed per-game home once, on the first
    /// run of an export that reads the new home and knows the old name.
    func migrateLegacySupportFolder() {
        guard let game = selectedGame, Self.validTitleID(game.titleID), appSupportName != "nxnative",
              usesFixedSupportHome else { return }
        let fm = FileManager.default
        let home = supportRoot.appendingPathComponent("nxnative", isDirectory: true)
            .appendingPathComponent(game.titleID, isDirectory: true)
        guard !fm.fileExists(atPath: home.appendingPathComponent("save").path) else { return }
        let legacy = supportRoot.appendingPathComponent(appSupportName, isDirectory: true)
        guard legacy.path != home.path, fm.fileExists(atPath: legacy.path) else { return }
        do {
            try Self.migrateFolder(from: legacy, to: home)
            appendLog("已迁移存档与设置：\(appSupportName) → nxnative/\(game.titleID)")
        } catch {
            appendLog("✗ 迁移旧存档目录失败：\(error.localizedDescription)（旧目录保留，下次启动再试）")
        }
    }

    /// Move `from` into `to`, file by file, never overwriting what is already there (a name present
    /// on both sides stays the new one; directories merge). The source folder remains when
    /// something was kept on both sides.
    nonisolated static func migrateFolder(from: URL, to: URL) throws {
        let fm = FileManager.default
        let sourceValues = try from.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard sourceValues.isDirectory == true, sourceValues.isSymbolicLink != true else { return }
        if fm.fileExists(atPath: to.path) {
            let values = try to.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { return }
        } else { try fm.createDirectory(at: to, withIntermediateDirectories: true) }
        for item in try fm.contentsOfDirectory(atPath: from.path) {
            let source = from.appendingPathComponent(item)
            let target = to.appendingPathComponent(item)
            // lstat-style resource checks also recognize broken symbolic links as conflicts.
            if (try? target.resourceValues(forKeys: [.isSymbolicLinkKey])) != nil {
                let sourceKind = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                let targetKind = try target.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if sourceKind.isDirectory == true, targetKind.isDirectory == true,
                   sourceKind.isSymbolicLink != true, targetKind.isSymbolicLink != true {
                    try migrateFolder(from: source, to: target)
                }
                continue // preserve BOTH conflicting files / types
            }
            try fm.moveItem(at: source, to: target)
        }
        if try fm.contentsOfDirectory(atPath: from.path).isEmpty { try fm.removeItem(at: from) }
    }

    /// The name of the legacy support folder: the name of the .app that is started (exports before
    /// the fixed per-game home built the app and its support folder with the same name). Before an
    /// app is known, the game's own name.
    var appSupportName: String {
        if let path = selectedGame?.appPath, !path.isEmpty {
            let name = (path as NSString).lastPathComponent
            return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
        }
        return supportName
    }

    var supportName: String {
        if let n = plan?.name, !n.isEmpty { return n }
        if let game = selectedGame, !game.titleID.isEmpty, !game.name.isEmpty { return game.name }
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
    /// The lines the launcher owns (the frame rate, the language, the operation mode and the
    /// mouse scheme) are rewritten; every other line is kept. Overwriting the whole file would
    /// silently drop what the user added by hand (DM_PADMAP, DM_AUDIO, ...).
    private var hasRuntimeContext: Bool {
        guard selectedGame != nil else { return false }
        return !(selectedGame?.appPath ?? "").isEmpty || supportName != "nxnative"
    }

    private struct RuntimeSettings: Equatable {
        var gameID: String?
        var supportPath: String
        var fps: Int
        var language: Language
        var mode: OpMode
    }
    private var appliedSettings: RuntimeSettings?
    private var runtimeSettings: RuntimeSettings {
        RuntimeSettings(gameID: selectedGameID, supportPath: supportDir.path,
                        fps: targetFPS, language: language, mode: opMode)
    }

    @discardableResult
    func writeEnv() -> Bool {
        guard hasRuntimeContext else { return false }
        let dir = supportDir
        let file = dir.appendingPathComponent("env.txt")
        var kept: [String] = []
        var hasAudio = false
        if let data = try? Data(contentsOf: file), let old = String(data: data, encoding: .utf8) {
            for raw in old.split(separator: "\n", omittingEmptySubsequences: false) {
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.isEmpty || line.hasPrefix("#") { continue }
                let key = line.split(separator: "=", maxSplits: 1).first.map(String.init) ?? ""
                if key == "DM_FPS_TARGET" || key == "DM_LANG" { continue }   // the launcher writes these
                if key == "DM_OPMODE" || key == "DM_MOUSE_PAD" { continue }  // and these (the mode decides both)
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
        // The operation mode, and what the mouse is: in handheld mode the mouse is the touch
        // screen (and the A button, since a console game has no touch UI at all); in console
        // mode there is no touch screen, so the mouse can only be a finger.
        lines.append("DM_OPMODE=\(opMode.code)")
        lines.append("DM_MOUSE_PAD=\(opMode.mouseConfirms ? 1 : 0)")
        lines.append(contentsOf: kept)
        let text = lines.joined(separator: "\n") + "\n"
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try text.write(to: file, atomically: true, encoding: .utf8)
        } catch {
            notify("写入游戏设置失败：\(error.localizedDescription)", isError: true)
            return false
        }
        appliedSettings = runtimeSettings
        let relative = supportDir.path.hasPrefix(supportRoot.path + "/")
            ? String(supportDir.path.dropFirst(supportRoot.path.count + 1))
            : supportDir.lastPathComponent
        notify("设置已写入 \(relative)/env.txt")
        return true
    }

    /// A read resets every picker, even if this game's env is absent, and records the complete
    /// applied snapshot. Deferred SwiftUI onChange callbacks therefore remain read-only.
    func loadEnv() {
        var fps = 60
        var lang: Language = .system
        var mode: OpMode = .handheld
        if hasRuntimeContext,
           let old = try? String(contentsOf: supportDir.appendingPathComponent("env.txt"), encoding: .utf8) {
            for raw in old.split(separator: "\n") {
                let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.hasPrefix("#") else { continue }
                let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else { continue }
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let value = parts[1].trimmingCharacters(in: .whitespaces)
                switch key {
                case "DM_FPS_TARGET": if let parsed = Int(value), parsed > 0 { fps = parsed }
                case "DM_LANG":
                    lang = value == "zh-Hans" ? .zhHans : value == "en-US" ? .enUS : .system
                case "DM_OPMODE": mode = value == "1" ? .console : .handheld
                default: break
                }
            }
        }
        targetFPS = fps
        language = lang
        opMode = mode
        appliedSettings = runtimeSettings
    }

    /// UI API: call for FPS, language AND operation-mode onChange. Reads do not write, including
    /// delayed onChange delivery after a game switch or plan refresh.
    func runtimeSettingsChanged() {
        guard !busy, hasRuntimeContext, appliedSettings != runtimeSettings else { return }
        let modeChanged = appliedSettings?.mode != opMode
        guard writeEnv() else { return }
        if modeChanged { showModeToast(opMode) }
    }

    func opModeChanged() { runtimeSettingsChanged() }

    @discardableResult
    func setOpMode(_ mode: OpMode) -> String {
        opMode = mode
        runtimeSettingsChanged()
        return modeMessage(mode)
    }

    private func modeMessage(_ mode: OpMode) -> String {
        mode == .console
            ? "已切换到主机模式：游戏按 1920×1080 渲染（窗口大于 1280×720 时更清晰）。"
              + "Switch 主机没有触摸屏，所以鼠标左键的点击确认不可用，请用键盘（方向键选择、J 确认）或手柄。下次启动生效。"
            : "已切换到掌机模式：游戏按 1280×720 渲染（与窗口 1:1，文字最锐），鼠标左键 = 确认键。下次启动生效。"
    }

    private func showModeToast(_ mode: OpMode) {
        showToast(modeMessage(mode), warning: mode == .console)
    }

    /// A message that floats over the window for a few seconds.
    func showToast(_ text: String, warning: Bool = false) {
        toast = text
        toastIsWarning = warning
        toastToken &+= 1
        let token = toastToken
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 9_000_000_000)
            if self.toastToken == token { self.toast = nil }
        }
    }
}
