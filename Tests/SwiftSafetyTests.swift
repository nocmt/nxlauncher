// Standalone, generated-fixture-only harness. Never opens Finder, launches games or installs tools.
import Foundation

@main
struct SwiftSafetyTests {
    @MainActor
    static func main() async throws {
        if CommandLine.arguments.count == 4 && CommandLine.arguments[1] == "--unpack" {
            print(try LauncherState.unpackArchive(URL(fileURLWithPath: CommandLine.arguments[2]),
                                                 cache: URL(fileURLWithPath: CommandLine.arguments[3])).path)
            return
        }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("NxSafety-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        func directory(_ name: String) throws -> URL {
            let url = root.appendingPathComponent(name)
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        func write(_ text: String, _ url: URL) throws { try text.write(to: url, atomically: true, encoding: .utf8) }
        let source = try directory("migration/source")
        let target = try directory("migration/target")
        try write("old", source.appendingPathComponent("conflict"))
        try write("new", target.appendingPathComponent("conflict"))
        try write("move", source.appendingPathComponent("unique"))
        _ = try directory("migration/source/dir-v-file")
        try write("retained", source.appendingPathComponent("dir-v-file/child"))
        try write("new file", target.appendingPathComponent("dir-v-file"))
        try write("old file", source.appendingPathComponent("file-v-dir"))
        _ = try directory("migration/target/file-v-dir")
        _ = try directory("migration/source/nested")
        _ = try directory("migration/target/nested")
        try write("old nested", source.appendingPathComponent("nested/conflict"))
        try write("new nested", target.appendingPathComponent("nested/conflict"))
        try write("nested unique", source.appendingPathComponent("nested/unique"))
        let outside = try directory("outside")
        try write("do not follow", outside.appendingPathComponent("sentinel"))
        try fm.createSymbolicLink(at: target.appendingPathComponent("linked"), withDestinationURL: outside)
        _ = try directory("migration/source/linked")
        try write("retained link conflict", source.appendingPathComponent("linked/child"))
        try LauncherState.migrateFolder(from: source, to: target)
        let oldConflict = try String(contentsOf: source.appendingPathComponent("conflict"), encoding: .utf8)
        let newConflict = try String(contentsOf: target.appendingPathComponent("conflict"), encoding: .utf8)
        precondition(oldConflict == "old" && newConflict == "new")
        precondition(fm.fileExists(atPath: source.appendingPathComponent("dir-v-file/child").path))
        precondition(fm.fileExists(atPath: source.appendingPathComponent("file-v-dir").path))
        precondition(fm.fileExists(atPath: source.appendingPathComponent("nested/conflict").path))
        precondition(fm.fileExists(atPath: target.appendingPathComponent("nested/unique").path))
        precondition(fm.fileExists(atPath: target.appendingPathComponent("unique").path))
        precondition(fm.fileExists(atPath: source.appendingPathComponent("linked/child").path))
        precondition(!fm.fileExists(atPath: outside.appendingPathComponent("child").path))
        let emptySource = try directory("migration/emptySource")
        try write("unique", emptySource.appendingPathComponent("unique"))
        try LauncherState.migrateFolder(from: emptySource, to: root.appendingPathComponent("migration/emptyTarget"))
        precondition(!fm.fileExists(atPath: emptySource.path))
        print("PASS: conflict preservation, nested merge, type conflicts, symlink isolation and empty-only source deletion")

        precondition(LauncherState.validTitleID("0100abcdefABCDEF"))
        for invalid in ["", "GameA", "../0100000000000", "010000000000000G", "0100000000000000/", "０１００００００００００００００"] {
            precondition(!LauncherState.validTitleID(invalid))
        }
        let support = try directory("support")
        let suite = "NxSafety.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = LauncherState(defaults: defaults, arguments: ["test"], home: root, supportRoot: support)
        let game = LibraryGame(folder: root.path, titleID: "010000000000000A")
        precondition(state.saveDirectory(for: game)?.path == support.appendingPathComponent("nxnative/010000000000000A/save").path)
        precondition(!fm.fileExists(atPath: state.saveDirectory(for: game)!.path), "Resolving a save path must not migrate or create anything")
        for i in 0..<650 { state.handle(.log("persistent-\(i)")) }
        precondition(state.logLines.count == 500 && state.completeLog.contains("persistent-0\n"))
        precondition(state.completeLog.contains("persistent-649"))
        state.handle(.diagnostic(id: "NX_FIXTURE", message: "fixture failure", hint: "retry fixture", session: "fixture-session"))
        state.recordPipelineFailure(Pipeline.Failure.exited(3, nil), operation: "编译")
        precondition(state.lastErrorID == "NX_FIXTURE" && state.errorHint == "retry fixture" && state.notice.contains("NX_FIXTURE"))
        print("PASS: strict Title ID, read-only save path resolution, full persistent log beyond 500 lines and stable diagnostics")

        guard case .diagnostic(let id, _, let hint, _) = decodeEvent(#"{"ev":"error","error_id":"NX_TEST","message":"failed","hint":"retry","session_id":"s"}"#) else { fatalError("diagnostic decoding") }
        precondition(id == "NX_TEST" && hint == "retry")
        guard case .session(let session, let path) = decodeEvent(#"{"ev":"session","session_id":"s","log_path":"/tmp/s.log"}"#) else { fatalError("session decoding") }
        precondition(session == "s" && path == "/tmp/s.log")
        guard case .artifact(let artifactTarget, _, _, _, _) = decodeEvent(#"{"ev":"artifact","target":"mac-app","path":"/tmp/Game.app","game":"010000000000000A"}"#) else { fatalError("artifact decoding") }
        precondition(artifactTarget == "mac-app")
        let repairJSON = #"{"id":"brew-zstd","argv":["brew","install","zstd"],"command":"must never be evaluated","requires_admin":false,"automatic":false}"#
        let repair = try JSONDecoder().decode(DependencyRepair.self, from: Data(repairJSON.utf8))
        precondition(repair.approvedArguments == ["install", "zstd"])
        let rejected = repairJSON.replacingOccurrences(of: "zstd", with: "evil; touch /tmp/evil")
        let rejectedRepair = try JSONDecoder().decode(DependencyRepair.self, from: Data(rejected.utf8))
        precondition(rejectedRepair.approvedArguments == nil)
        let report = try JSONDecoder().decode(DependencyReport.self, from: Data(#"{"ready":false,"checks":[],"commands":[]}"#.utf8))
        precondition(report.repairs == nil)
        print("PASS: error/session/artifact contracts, legacy dependency report and strict Homebrew repair allowlist")

        let cache = try directory("cache")
        let oldHome = try directory("cache/home")
        try write("old-home-must-survive", oldHome.appendingPathComponent("sentinel"))
        let corrupt = root.appendingPathComponent("corrupt.tgz")
        try write("not a gzip", corrupt)
        do { _ = try LauncherState.unpackArchive(corrupt, cache: cache); fatalError("Corrupt archive accepted") }
        catch { precondition(fm.fileExists(atPath: oldHome.appendingPathComponent("sentinel").path)) }
        let afterCorrupt = try fm.contentsOfDirectory(atPath: cache.appendingPathComponent("homes").path)
        precondition(!afterCorrupt.contains { $0.hasPrefix(".staging") })

        let payload = try directory("payload")
        _ = try directory("payload/Tools")
        _ = try directory("payload/python/bin")
        try write("# fixture", payload.appendingPathComponent("Tools/pack_pipeline.py"))
        let marker = root.appendingPathComponent("verification-ready")
        // A harmless fixture interpreter simulates failed imports, pip, and post-install imports.
        // It never installs packages or invokes Python; every call is recorded outside the cache.
        let calls = root.appendingPathComponent("calls.log")
        let fixturePython = """
        #!/bin/sh
        printf '%s\\n' "$*" >> '\(calls.path)'
        if [ ! -f '\(marker.path)' ]; then exit 9; fi
        exit 0
        """
        try write(fixturePython, payload.appendingPathComponent("python/bin/python3"))
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: payload.appendingPathComponent("python/bin/python3").path)
        let archive = root.appendingPathComponent("fixture.tgz")
        try LauncherState.run("/usr/bin/tar", ["-czf", archive.path, "-C", payload.path, "."])
        let digest = try LauncherState.archiveDigest(archive)
        let destination = cache.appendingPathComponent("homes/\(digest)")
        let preparing = LauncherState(defaults: defaults, arguments: ["test"], home: destination, supportRoot: support,
                                      preparationArchive: archive, preparationCache: cache)
        var downstream = 0
        preparing.prepare { downstream += 1 }
        while preparing.preparing { try await Task.sleep(nanoseconds: 10_000_000) }
        precondition(downstream == 0 && !preparing.preparationReady && !preparing.preparationError.isEmpty)
        precondition(!fm.fileExists(atPath: destination.path), "Failed offline verification cannot enable a home")
        let failedCalls = try String(contentsOf: calls, encoding: .utf8)
        precondition(failedCalls.contains("--no-index") && failedCalls.contains("--target"))
        try write("ready", marker)
        preparing.prepare { downstream += 1 }
        while preparing.preparing { try await Task.sleep(nanoseconds: 10_000_000) }
        precondition(downstream == 1 && preparing.preparationReady && preparing.preparationError.isEmpty)
        precondition(fm.fileExists(atPath: destination.appendingPathComponent(".ready").path))
        precondition(fm.fileExists(atPath: oldHome.appendingPathComponent("sentinel").path))
        print("PASS: corrupt archive, failed offline install stops downstream, retry, verification-before-publish and old home preservation")

        // Two independent executable processes unpack the same archive into one fresh cache.
        let concurrentCache = try directory("concurrent-cache")
        var children: [Process] = []
        for _ in 0..<2 {
            let child = Process()
            child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            child.arguments = ["--unpack", archive.path, concurrentCache.path]
            child.standardOutput = FileHandle.nullDevice
            try child.run()
            children.append(child)
        }
        for child in children { child.waitUntilExit(); precondition(child.terminationStatus == 0) }
        let published = try fm.contentsOfDirectory(atPath: concurrentCache.appendingPathComponent("homes").path)
        precondition(published == [digest], "Cross-process locking publishes exactly one home")
        let firstData = Data("123456".utf8), secondData = Data("654321".utf8)
        let hashA = root.appendingPathComponent("hash-a"), hashB = root.appendingPathComponent("hash-b")
        try firstData.write(to: hashA); try secondData.write(to: hashB)
        let sameDate = Date(timeIntervalSince1970: 100)
        try fm.setAttributes([.modificationDate: sameDate], ofItemAtPath: hashA.path)
        try fm.setAttributes([.modificationDate: sameDate], ofItemAtPath: hashB.path)
        let digestA = try LauncherState.archiveDigest(hashA), digestB = try LauncherState.archiveDigest(hashB)
        precondition(digestA != digestB, "Hash must use contents, not size/mtime")
        print("PASS: cross-process cache lock and content hashing independent of file size/mtime")
    }
}
