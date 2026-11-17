import Foundation
import UniformTypeIdentifiers

enum RemotePath {
    static func join(_ directory: String, _ name: String) -> String {
        directory == "/" ? "/\(name)" : "\(directory)/\(name)"
    }

    static func parent(of path: String) -> String {
        let parent = (path as NSString).deletingLastPathComponent
        return parent.isEmpty ? "/" : parent
    }
}

struct RemoteFile: Identifiable, Hashable {
    let path: String
    let name: String
    let isDirectory: Bool
    let size: Int64
    let modified: Date
    let kind: String
    let iconName: String

    var id: String { path }

    init(path: String, name: String, isDirectory: Bool, size: Int64, modified: Date) {
        self.path = path
        self.name = name
        self.isDirectory = isDirectory
        self.size = isDirectory ? -1 : size
        self.modified = modified

        let ext = (name as NSString).pathExtension.lowercased()
        let type = ext.isEmpty ? nil : UTType(filenameExtension: ext)
        if isDirectory {
            kind = "Folder"
            iconName = "folder.fill"
        } else {
            kind = type?.localizedDescription ?? (ext.isEmpty ? "File" : "\(ext.uppercased()) file")
            iconName = RemoteFile.icon(for: ext, type: type)
        }
    }

    private static func icon(for ext: String, type: UTType?) -> String {
        if ext == "apk" || ext == "xapk" { return "shippingbox" }
        guard let type else { return "doc" }
        if type.conforms(to: .image) { return "photo" }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return "film" }
        if type.conforms(to: .audio) { return "music.note" }
        if type.conforms(to: .pdf) { return "doc.richtext" }
        if type.conforms(to: .archive) { return "doc.zipper" }
        if type.conforms(to: .text) || type.conforms(to: .sourceCode) { return "doc.text" }
        return "doc"
    }

    /// Parses lines of `stat -L -c '%F|%s|%Y|%n'`.
    static func parse(_ output: String, in directory: String) -> [RemoteFile] {
        output.split(separator: "\n").compactMap { raw in
            let line = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            let parts = line.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false)
            guard parts.count == 4,
                  let size = Int64(parts[1]),
                  let mtime = TimeInterval(parts[2]) else { return nil }
            let name = (String(parts[3]) as NSString).lastPathComponent
            guard !name.isEmpty, name != ".", name != ".." else { return nil }
            return RemoteFile(
                path: RemotePath.join(directory, name),
                name: name,
                isDirectory: parts[0] == "directory",
                size: size,
                modified: Date(timeIntervalSince1970: mtime)
            )
        }
    }
}
