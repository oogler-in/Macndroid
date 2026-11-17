import AppKit
import UniformTypeIdentifiers

@MainActor
enum Panels {
    static var downloadsFolder: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    private static let lastDownloadKey = "lastDownloadFolder"

    static func chooseFilesToUpload() -> [URL] {
        let panel = NSOpenPanel()
        panel.title = "Choose Files to Copy to Your Device"
        panel.prompt = "Copy"
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        return panel.runModal() == .OK ? panel.urls : []
    }

    static func chooseAPKs() -> [URL] {
        let panel = NSOpenPanel()
        panel.title = "Choose Android Apps to Install"
        panel.prompt = "Install"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if let apk = UTType(filenameExtension: "apk") { panel.allowedContentTypes = [apk] }
        return panel.runModal() == .OK ? panel.urls : []
    }

    static func chooseDownloadFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose Where to Save"
        panel.prompt = "Save Here"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        if let saved = UserDefaults.standard.string(forKey: lastDownloadKey) {
            panel.directoryURL = URL(fileURLWithPath: saved)
        } else {
            panel.directoryURL = downloadsFolder
        }
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        UserDefaults.standard.set(url.path, forKey: lastDownloadKey)
        return url
    }
}
