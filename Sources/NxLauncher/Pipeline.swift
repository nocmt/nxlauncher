// The pipeline: run Tools/pack_pipeline.py and read its event stream.
//
// The vocabulary is the one the upstream packing script emits with --progress json (stage / step /
// progress / stage_end / say), plus {"ev":"log"} for the tools' own output. Everything arrives as one
// JSON object per line on stdout.
import Foundation

enum PipelineEvent {
    case stage(name: String, step: String)
    case progress(name: String, step: String, done: Double?, total: Double?, frac: Double?, note: String)
    case stageEnd(name: String, ok: Bool, summary: String)
    case say(String)
    case log(String)
    case plan(Plan)
    case games([GamesEntry])
    case error(String)
}

struct GamesEntry: Decodable, Identifiable {
    var titleID: String = ""
    var name: String = ""
    var version: String = ""
    var id: String { titleID }

    enum CodingKeys: String, CodingKey {
        case titleID = "title_id"
        case name, version
    }
}

/// Decodes one line of the event stream.
func decodeEvent(_ line: String) -> PipelineEvent? {
    guard let data = line.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let ev = obj["ev"] as? String else { return nil }

    func str(_ k: String) -> String { obj[k] as? String ?? "" }
    func num(_ k: String) -> Double? { obj[k] as? Double ?? (obj[k] as? NSNumber)?.doubleValue }
    func bool(_ k: String) -> Bool { obj[k] as? Bool ?? false }

    switch ev {
    case "stage":
        return .stage(name: str("name"), step: str("step"))
    case "progress":
        return .progress(name: str("name"), step: str("step"), done: num("done"), total: num("total"),
                         frac: num("frac"), note: str("note"))
    case "stage_end":
        return .stageEnd(name: str("name"), ok: bool("ok"), summary: str("summary"))
    case "say":
        return .say(str("msg"))
    case "log":
        return .log(str("line"))
    case "plan":
        if let data = line.data(using: .utf8), let p = try? JSONDecoder().decode(Plan.self, from: data) {
            return .plan(p)
        }
        return nil
    case "games":
        if let data = line.data(using: .utf8),
           let arr = try? JSONDecoder().decode([GamesEntry].self, from: data) {
            return .games(arr)
        }
        return nil
    case "error":
        return .error(str("message"))
    default:
        return nil
    }
}

/// Runs the pipeline script and calls back for every event.
final class Pipeline {
    enum Failure: Error { case cannotRun(String), exited(Int) }

    private let toolsDir: URL
    private let python: String

    init(toolsDir: URL, python: String = "/usr/bin/env") {
        self.toolsDir = toolsDir
        self.python = python
    }

    /// The script's path.
    var scriptURL: URL { toolsDir.appendingPathComponent("pack_pipeline.py") }

    /// Run it with the given arguments; `onEvent` is called for every line, on a background queue.
    func run(_ args: [String], onEvent: @escaping (PipelineEvent) -> Void) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", scriptURL.path] + args
        process.currentDirectoryURL = toolsDir
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        var buffer = Data()
        let group = DispatchGroup()
        group.enter()
        var exitCode: Int32 = 0

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                group.leave()
                return
            }
            buffer.append(chunk)
            while let idx = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer.subdata(in: buffer.startIndex..<idx)
                buffer.removeSubrange(buffer.startIndex...idx)
                guard let line = String(data: lineData, encoding: .utf8) else { continue }
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { continue }
                if let e = decodeEvent(trimmed) { onEvent(e) } else { onEvent(.log(trimmed)) }
            }
        }

        do {
            try process.run()
        } catch {
            group.leave()
            throw Failure.cannotRun(error.localizedDescription)
        }
        group.wait()
        process.waitUntilExit()
        exitCode = process.terminationStatus
        if exitCode != 0 { throw Failure.exited(Int(exitCode)) }
    }
}
