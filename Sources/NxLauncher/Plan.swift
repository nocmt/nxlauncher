// The plan: what the pipeline found in the game folder. One JSON object, decoded from
// Tools/pack_pipeline.py's "plan" command.
import Foundation

struct Plan: Decodable {
    var ev: String = ""
    var ok: Bool = false
    var error: String?

    var gameDir: String = ""
    var repo: String = ""
    var repoOK: Bool = false

    var keys: String = ""
    var keysOK: Bool = false

    var base: String = ""
    var baseTitleID: String = ""
    var updates: [String] = []
    var dlc: [String] = []
    var allFiles: [String] = []

    var hasPort: Bool = false
    var name: String = ""
    var version: String = ""
    var workDir: String = ""
    var built: Bool = false
    var icon: String = ""
    var fpsTarget: String = ""
    var notes: [String] = []

    enum CodingKeys: String, CodingKey {
        case ev, ok, error
        case gameDir = "game_dir"
        case repo, repoOK = "repo_ok"
        case keys, keysOK = "keys_ok"
        case base, updates, dlc
        case allFiles = "all_files"
        case hasPort = "has_port"
        case baseTitleID = "base_title_id"
        case name, version
        case workDir = "work_dir"
        case built, icon
        case fpsTarget = "fps_target"
        case notes
    }

    /// The file name of a path, for the one-line rows of the list.
    static func fileName(_ path: String) -> String {
        path.isEmpty ? "" : (path as NSString).lastPathComponent
    }
}
