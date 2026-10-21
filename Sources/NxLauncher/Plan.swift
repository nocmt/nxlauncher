// The plan: what the pipeline found in the game folder. One JSON object, decoded from
// Tools/pack_pipeline.py's "plan" command.
import Foundation

/// One file in the game folder: the base game, an update, or a DLC.
///
/// The title ID and the name are kept apart on purpose: the ID is 16 characters and always fits on
/// a line, the name can be long. A folder can hold several updates and several DLC, so they are
/// listed one by one rather than as one joined string.
struct GameFile: Decodable, Identifiable {
    var path: String = ""
    var name: String = ""
    /// The name without the title ID in it (the ID is shown on its own).
    var label: String = ""
    var titleID: String = ""

    var id: String { path }

    enum CodingKeys: String, CodingKey {
        case path, name, label
        case titleID = "title_id"
    }
}

struct Plan: Decodable {
    var ev: String = ""
    var ok: Bool = false
    var error: String?

    var gameDir: String = ""
    var repo: String = ""
    var repoOK: Bool = false

    var keys: String = ""
    var keysOK: Bool = false

    var base: GameFile? = nil
    var baseTitleID: String = ""
    var updates: [GameFile] = []
    var dlc: [GameFile] = []
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
}
