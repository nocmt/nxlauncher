// Standalone harness; compile alongside GameLibrary, LauncherState, Plan and Pipeline.
// Uses only generated fixtures, a private defaults suite and temporary support directories.
import Foundation

@main
struct GameLibraryTests {
    @MainActor
    static func main() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("NxLibraryTests-\(UUID().uuidString)")
        let suite = "NxLibraryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); try? fm.removeItem(at: root) }
        func directory(_ path: String) throws -> URL {
            let url = root.appendingPathComponent(path)
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        let tools = try directory("Tools")
        let support = try directory("support")
        let folderA = try directory("GameA")
        let folderB = try directory("GameB")
        let exports = try directory("exports")
        let appA = try directory("exports/RenamedA.app")
        _ = try directory("exports/Unrelated.app")
        let envA = try directory("support/RenamedA").appendingPathComponent("env.txt")
        let originalEnv = "# fixture\nDM_FPS_TARGET=30\nDM_LANG=en-US\nDM_OPMODE=1\nDM_PADMAP=custom\n"
        try originalEnv.write(to: envA, atomically: true, encoding: .utf8)
        let script = """
        import sys,json,os
        assert sys.argv[1] == 'plan', 'Harness must never build/export'
        folder=sys.argv[sys.argv.index('--game-dir')+1]
        name=os.path.basename(folder)
        p=dict(ev='plan',ok=True,game_dir=folder,repo='',repo_ok=False,keys='',keys_ok=False,
          base=None,base_title_id=name,updates=[],dlc=[],all_files=[],has_port=False,
          name=name,version='1.2',work_dir=folder+'/work',built=False,icon='',fps_target='',notes=[])
        print(json.dumps(p),flush=True)
        """
        try script.write(to: tools.appendingPathComponent("pack_pipeline.py"), atomically: true, encoding: .utf8)

        let minimal = try JSONDecoder().decode(LibraryGame.self, from: Data("{\"folder\":\"\(folderA.path)\"}".utf8))
        precondition(minimal.id == folderA.path && minimal.appPath.isEmpty && !minimal.built)
        let a = LibraryGame(folder: folderA.path, name: "GameA", appPath: appA.path)
        let b = LibraryGame(folder: folderB.path, name: "GameB")
        let store = GameLibraryStore(defaults: defaults)
        store.save([a, b], selectedID: a.id)
        defaults.set(appA.path, forKey: "gameAppPath")
        let state = LauncherState(defaults: defaults, arguments: ["test"], home: root, supportRoot: support)
        state.exportDir = exports.path
        precondition(state.library.count == 2 && state.selectedGameID == a.id)
        precondition(state.targetFPS == 30 && state.language == .enUS && state.opMode == .console)
        state.runtimeSettingsChanged()
        state.loadEnv()
        state.runtimeSettingsChanged()
        let afterRead = try String(contentsOf: envA, encoding: .utf8)
        precondition(afterRead == originalEnv)
        precondition(state.logLines.isEmpty, "Read callbacks must not write or notify")
        precondition(state.findGameApp()?.path == appA.path)

        // Queued plan A must not land on B; loading B's absent env resets all runtime values.
        state.selectGame(a)
        state.selectGame(b)
        try await Task.sleep(nanoseconds: 100_000_000)
        precondition(state.plan?.gameDir == folderB.path && state.plan?.name == "GameB")
        precondition(state.targetFPS == 60 && state.language == .system && state.opMode == .handheld)
        precondition(state.findGameApp() == nil, "Never use another game's legacy pointer or arbitrary .app")
        state.runtimeSettingsChanged()
        precondition(!fm.fileExists(atPath: support.appendingPathComponent("GameB").path))
        let expectedB = try directory("exports/GameB.app")
        precondition(state.findGameApp()?.path == expectedB.path)
        try fm.removeItem(at: expectedB)
        state.gameAppPath = appA.path // Public legacy property cannot change B's association.
        precondition(state.findGameApp() == nil)

        // Persisted keys are paths only; the referenced key file need not exist.
        let keyURL = root.appendingPathComponent("never-created.keys")
        state.setKeys(keyURL)
        precondition(defaults.string(forKey: "keysPath") == keyURL.path)
        precondition(!fm.fileExists(atPath: keyURL.path))
        state.busy = true
        state.selectGame(a)
        state.removeGame(b)
        let folderC = try directory("GameC")
        state.addGameFolder(folderC)
        state.setKeys(root.appendingPathComponent("different.keys"))
        precondition(state.selectedGameID == b.id && state.library.count == 2 && state.keysPath == keyURL.path)
        state.busy = false

        state.selectGame(a)
        try await Task.sleep(nanoseconds: 100_000_000)
        precondition(state.targetFPS == 30 && state.language == .enUS && state.opMode == .console)
        state.targetFPS = 120
        state.runtimeSettingsChanged()
        let written = try String(contentsOf: envA, encoding: .utf8)
        precondition(written.contains("DM_FPS_TARGET=120") && written.contains("DM_PADMAP=custom"))
        state.runtimeSettingsChanged()
        state.loadEnv()
        state.runtimeSettingsChanged()
        let afterReload = try String(contentsOf: envA, encoding: .utf8)
        precondition(afterReload == written)
        precondition(state.library.first(where: { $0.id == a.id })?.version == "1.2")
        precondition(state.library.first(where: { $0.id == a.id })?.appPath == appA.path)
        let restored = LauncherState(defaults: defaults, arguments: ["test"], home: root, supportRoot: support)
        precondition(restored.selectedGameID == a.id && restored.keysPath == keyURL.path)
        precondition(restored.targetFPS == 120 && restored.findGameApp()?.path == appA.path)

        state.toggleGameSelection(a)
        precondition(state.selectedGameID == nil && state.gameDir.isEmpty && state.gameAppPath.isEmpty)
        precondition(state.plan == nil && state.library.count == 2)
        precondition(defaults.string(forKey: GameLibraryStore.selectionKey) == nil)
        let deselected = LauncherState(defaults: defaults, arguments: ["test"], home: root, supportRoot: support)
        precondition(deselected.selectedGameID == nil && deselected.gameDir.isEmpty)
        state.toggleGameSelection(a)
        precondition(state.selectedGameID == a.id)
        state.toggleGameSelection(b)
        precondition(state.selectedGameID == b.id)
        state.busy = true
        state.toggleGameSelection(b)
        state.toggleGameSelection(a)
        precondition(state.selectedGameID == b.id)
        state.busy = false
        state.toggleGameSelection(b)
        try await Task.sleep(nanoseconds: 100_000_000)
        precondition(state.selectedGameID == nil && state.plan == nil && state.gameDir.isEmpty,
                     "Queued plans must not restore a deselected game")
        precondition(store.load().count == 2 && fm.fileExists(atPath: envA.path))
        state.selectGame(a)

        // Removal only drops references; stale queued plans cannot recreate removed entries.
        state.removeGame(a)
        state.removeGame(b)
        try await Task.sleep(nanoseconds: 100_000_000)
        precondition(state.library.isEmpty && state.selectedGameID == nil && state.plan == nil)
        precondition(fm.fileExists(atPath: folderA.path) && fm.fileExists(atPath: appA.path))
        precondition(fm.fileExists(atPath: envA.path))
        precondition(!state.writeEnv())
        state.runtimeSettingsChanged()
        precondition(!fm.fileExists(atPath: support.appendingPathComponent("nxnative").path))
        precondition(store.load().isEmpty)

        // Canonical symlink duplicates collapse; explicit CLI folder registers only on refresh.
        let alias = root.appendingPathComponent("AliasA")
        try fm.createSymbolicLink(at: alias, withDestinationURL: folderA)
        let cli = LauncherState(defaults: defaults, arguments: ["test", "--game-dir", alias.path],
                                home: root, supportRoot: support)
        cli.exportDir = exports.path
        precondition(cli.library.isEmpty)
        cli.refreshPlan()
        try await Task.sleep(nanoseconds: 100_000_000)
        precondition(cli.library.count == 1 && cli.selectedGameID == a.id)
        cli.addGameFolder(alias)
        try await Task.sleep(nanoseconds: 100_000_000)
        precondition(cli.library.count == 1)
        precondition(cli.findGameApp() == nil, "Renamed legacy app is not demonstrably associated")
        print("PASS: Codable defaults, canonical identity, persistence, keys path, settings reads/writes, cross-game app isolation, stale plans, busy guards, reference-only removal and CLI registration")
    }
}
