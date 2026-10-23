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
    case dependencies(DependencyReport)
    case error(String)
}

struct DependencyCheck: Decodable, Identifiable {
    let id: String
    let name: String
    let ok: Bool
    let detail: String
    let hint: String
}

struct DependencyReport: Decodable {
    let ready: Bool
    let checks: [DependencyCheck]
    let commands: [String]
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
    case "dependencies":
        if let report = try? JSONDecoder().decode(DependencyReport.self, from: Data(line.utf8)) {
            return .dependencies(report)
        }
        return nil
    case "error":
        return .error(str("message"))
    default:
        return nil
    }
}

/// Runs the pipeline script and calls back for every event.
/// It holds no mutable state (the process is local to run()), so it is safe to hand to a background
/// queue.
final class Pipeline: @unchecked Sendable {
    enum Failure: LocalizedError {
        case cannotRun(String)
        case exited(Int, String?)

        var errorDescription: String? {
            switch self {
            case .cannotRun(let message):
                return "Cannot run pipeline: \(message)"
            case .exited(let code, let diagnostic):
                let message = "Pipeline exited with status \(code)"
                return diagnostic.map { "\(message): \($0)" } ?? message
            }
        }
    }

    private let toolsDir: URL
    /// The interpreter to run the script with; nil = the system's python3.
    private let python: String?
    /// Extra environment for the script (the bundled tree, the bundled Python's packages).
    private let env: [String: String]

    init(toolsDir: URL, python: String? = nil, env: [String: String] = [:]) {
        self.toolsDir = toolsDir
        self.python = python
        self.env = env
    }

    /// The script's path.
    var scriptURL: URL { toolsDir.appendingPathComponent("pack_pipeline.py") }

    /// Run it with the given arguments; `onEvent` is called for every line, on a background queue.
    func run(_ args: [String], onEvent: @escaping (PipelineEvent) -> Void) throws {
        let process = Process()
        if let python {
            process.executableURL = URL(fileURLWithPath: python)
            process.arguments = [scriptURL.path] + args
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["python3", scriptURL.path] + args
        }
        process.currentDirectoryURL = toolsDir
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        for (k, v) in env { environment[k] = v }
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        var buffer = Data()
        var lastError: String?
        var recentOutput: [String] = []

        func consumeLine(_ data: Data) {
            let line = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { return }
            let event = decodeEvent(line) ?? .log(line)
            var diagnostic: String?
            switch event {
            case .error(let message):
                if !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    lastError = message
                }
            case .log(let message), .say(let message):
                diagnostic = message
            case .stageEnd(_, false, let summary):
                diagnostic = summary
            default:
                break
            }
            if let diagnostic, !diagnostic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                recentOutput.append(diagnostic)
                if recentOutput.count > 10 { recentOutput.removeFirst() }
            }
            onEvent(event)
        }

        let group = DispatchGroup()
        group.enter()

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                if !buffer.isEmpty { consumeLine(buffer) }
                group.leave()
                return
            }
            buffer.append(chunk)
            while let idx = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer.subdata(in: buffer.startIndex..<idx)
                buffer.removeSubrange(buffer.startIndex...idx)
                consumeLine(lineData)
            }
        }

        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            group.leave()
            throw Failure.cannotRun(error.localizedDescription)
        }
        group.wait()
        process.waitUntilExit()
        let exitCode = process.terminationStatus
        if exitCode != 0 {
            let diagnostic = lastError ?? (recentOutput.isEmpty ? nil : recentOutput.joined(separator: "\n"))
            throw Failure.exited(Int(exitCode), diagnostic)
        }
    }
}
