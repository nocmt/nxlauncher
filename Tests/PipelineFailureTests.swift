// Standalone macOS harness. Run from the repository root with:
// swiftc Sources/NxLauncher/Plan.swift Sources/NxLauncher/Pipeline.swift Tests/PipelineFailureTests.swift -o /tmp/PipelineFailureTests && /tmp/PipelineFailureTests
import Foundation

@main
struct PipelineFailureTests {
    static func main() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("NxLauncher-PipelineFailureTests-\(UUID().uuidString)")
        let tools = root.appendingPathComponent("Tools")
        try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let script = tools.appendingPathComponent("pack_pipeline.py")
        try """
        import json
        print(json.dumps({"ev": "log", "line": "first detailed line"}), flush=True)
        print(json.dumps({"ev": "error", "message": "specific detailed failure"}), flush=True)
        print(json.dumps({"ev": "stage_end", "name": "build", "ok": False, "summary": "the script exited 7"}), flush=True)
        raise SystemExit(7)
        """.write(to: script, atomically: true, encoding: .utf8)

        var events: [PipelineEvent] = []
        do {
            try Pipeline(toolsDir: tools).run([]) { events.append($0) }
            preconditionFailure("The failing pipeline must throw")
        } catch let failure as Pipeline.Failure {
            precondition(failure.localizedDescription == "Pipeline exited with status 7",
                         "The surfaced failure must not contain streamed output")
            precondition(failure.notice(operation: "编译") == "编译失败（退出码 7），详情见构建日志")
            precondition(failure.diagnostic == "specific detailed failure")
        }

        precondition(events.count == 3, "Every streamed diagnostic must remain an event")
        if case .log(let line) = events[0] { precondition(line == "first detailed line") }
        else { preconditionFailure("The first event must be the log line") }
        if case .error(let message) = events[1] { precondition(message == "specific detailed failure") }
        else { preconditionFailure("The structured error must remain in the log stream") }
        if case .stageEnd(let name, let ok, let summary) = events[2] {
            precondition(name == "build" && !ok && summary == "the script exited 7")
        } else { preconditionFailure("The failed stage must remain in the log stream") }

        let unavailable = Pipeline.Failure.cannotRun("No such file")
        precondition(unavailable.notice(operation: "导出") == "导出失败，无法启动构建流程，详情见构建日志")
        precondition(unavailable.diagnostic == "Cannot run pipeline: No such file")

        let gameLine = #"{"ev":"games","games":[{"title_id":"01006F8002326000","name":"Animal Crossing","version":"v2228224"}],"count":1}"#
        guard case .games(let games) = decodeEvent(gameLine) else {
            preconditionFailure("The games envelope must decode as an event, not raw log output")
        }
        precondition(games.count == 1 && games[0].titleID == "01006F8002326000")
        print("PASS: short pipeline failures and games envelope decoding")
    }
}
