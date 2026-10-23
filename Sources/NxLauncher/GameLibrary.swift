import Foundation

/// A library entry is a reference, never ownership of the game's files or saves.
struct LibraryGame: Codable, Identifiable, Equatable {
    var id: String
    var folder: String
    var name: String
    var icon: String
    var version: String
    var titleID: String
    var built: Bool
    var appPath: String

    init(id: String? = nil, folder: String, name: String = "", icon: String = "",
         version: String = "", titleID: String = "", built: Bool = false, appPath: String = "") {
        let path = Self.canonicalPath(folder)
        self.id = path
        self.folder = path
        self.name = name.isEmpty ? URL(fileURLWithPath: path).lastPathComponent : name
        self.icon = icon
        self.version = version
        self.titleID = titleID
        self.built = built
        self.appPath = appPath
    }

    static func canonicalPath(_ path: String) -> String {
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            .standardizedFileURL.resolvingSymlinksInPath().path
    }

    enum CodingKeys: String, CodingKey {
        case id, folder, name, icon, version, titleID, built, appPath
    }

    /// Old entries may omit any metadata; identity is always recomputed from the folder.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let folder = try values.decodeIfPresent(String.self, forKey: .folder)
            ?? values.decodeIfPresent(String.self, forKey: .id) ?? ""
        guard !Self.canonicalPath(folder).isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .folder, in: values,
                                                   debugDescription: "Missing game folder")
        }
        self.init(folder: folder,
                  name: try values.decodeIfPresent(String.self, forKey: .name) ?? "",
                  icon: try values.decodeIfPresent(String.self, forKey: .icon) ?? "",
                  version: try values.decodeIfPresent(String.self, forKey: .version) ?? "",
                  titleID: try values.decodeIfPresent(String.self, forKey: .titleID) ?? "",
                  built: try values.decodeIfPresent(Bool.self, forKey: .built) ?? false,
                  appPath: try values.decodeIfPresent(String.self, forKey: .appPath) ?? "")
    }
}

/// UserDefaults stores references and metadata only. No directory enumeration or key reads.
struct GameLibraryStore {
    let defaults: UserDefaults
    static let libraryKey = "gameLibrary"
    static let selectionKey = "selectedGameID"
    static let keysKey = "keysPath"

    func load() -> [LibraryGame] {
        guard let data = defaults.data(forKey: Self.libraryKey),
              let entries = try? JSONDecoder().decode([LibraryGame].self, from: data) else { return [] }
        var seen = Set<String>()
        return entries.filter { !$0.folder.isEmpty && seen.insert($0.id).inserted }
    }

    func save(_ games: [LibraryGame], selectedID: String?) {
        guard let data = try? JSONEncoder().encode(games) else { return }
        defaults.set(data, forKey: Self.libraryKey)
        if let selectedID { defaults.set(selectedID, forKey: Self.selectionKey) }
        else { defaults.removeObject(forKey: Self.selectionKey) }
    }
}
