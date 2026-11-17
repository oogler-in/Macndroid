import Foundation
import Observation

@MainActor
@Observable
final class BrowserModel {
    let serial: String
    @ObservationIgnored private let adb: ADBClient

    private(set) var path: String
    private(set) var files: [RemoteFile] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    var searchText = ""
    var showHidden = false
    var sortOrder: [KeyPathComparator<RemoteFile>] = [KeyPathComparator(\RemoteFile.name, comparator: .localizedStandard)]

    private var backStack: [String] = []
    private var forwardStack: [String] = []
    @ObservationIgnored private var loadGeneration = 0

    init(serial: String, adb: ADBClient, path: String = "/sdcard") {
        self.serial = serial
        self.adb = adb
        self.path = path
    }

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }
    var canGoUp: Bool { path != "/" }

    /// Filtered and sorted, folders first.
    var displayedFiles: [RemoteFile] {
        var list = files
        if !showHidden { list.removeAll { $0.name.hasPrefix(".") } }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty { list.removeAll { !$0.name.localizedCaseInsensitiveContains(query) } }
        list.sort(using: sortOrder)
        return list.filter(\.isDirectory) + list.filter { !$0.isDirectory }
    }

    // MARK: Navigation

    func navigate(to newPath: String) {
        guard newPath != path else {
            Task { await reload() }
            return
        }
        backStack.append(path)
        forwardStack.removeAll()
        setPath(newPath)
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(path)
        setPath(previous)
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(path)
        setPath(next)
    }

    func goUp() {
        guard canGoUp else { return }
        navigate(to: RemotePath.parent(of: path))
    }

    private func setPath(_ newPath: String) {
        path = newPath
        files = []
        searchText = ""
        Task { await reload() }
    }

    func reload() async {
        loadGeneration += 1
        let generation = loadGeneration
        let current = path
        isLoading = true

        let dir = current == "/" ? "/" : current + "/"
        let quoted = dir.shellQuoted
        let command = """
        if [ -d \(quoted) ] && [ -x \(quoted) ]; then \
        find \(quoted) -mindepth 1 -maxdepth 1 -exec stat -L -c '%F|%s|%Y|%n' {} + 2>/dev/null; \
        else echo __MACNDROID_NOACCESS__; fi
        """
        do {
            let result = try await adb.shell(serial, command)
            guard generation == loadGeneration else { return }
            if result.stdout.contains("__MACNDROID_NOACCESS__") {
                files = []
                errorMessage = "This folder doesn't exist or can't be opened."
            } else {
                files = RemoteFile.parse(result.stdout, in: current)
                errorMessage = nil
            }
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: File operations

    func makeDirectory(named name: String) async throws {
        let target = RemotePath.join(path, try validated(name))
        try await check(adb.shell(serial, "mkdir -p \(target.shellQuoted)"))
        await reload()
    }

    func rename(_ file: RemoteFile, to newName: String) async throws {
        let target = RemotePath.join(RemotePath.parent(of: file.path), try validated(newName))
        guard target != file.path else { return }
        try await check(adb.shell(serial, "mv -n \(file.path.shellQuoted) \(target.shellQuoted)"))
        await reload()
    }

    func delete(_ targets: [RemoteFile]) async throws {
        guard !targets.isEmpty else { return }
        let args = targets.map(\.path.shellQuoted).joined(separator: " ")
        try await check(adb.shell(serial, "rm -rf \(args)"))
        await reload()
    }

    private func validated(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != ".", trimmed != "..", !trimmed.contains("/") else {
            throw ADBError(message: "“\(name)” isn't a valid name.")
        }
        return trimmed
    }

    private func check(_ result: CommandResult) throws {
        if !result.succeeded { throw ADBError(message: result.errorSummary) }
    }
}
