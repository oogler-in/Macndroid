import SwiftUI
import UniformTypeIdentifiers

struct FileBrowserView: View {
    @Environment(AppModel.self) private var app
    let device: Device
    @State private var browser: BrowserModel
    @State private var selection = Set<RemoteFile.ID>()
    @State private var dropTargeted = false

    @State private var showingNewFolder = false
    @State private var newFolderName = ""
    @State private var renaming: RemoteFile?
    @State private var renameText = ""
    @State private var pendingDelete: [RemoteFile] = []
    @State private var showingDeleteConfirm = false

    init(device: Device, adb: ADBClient) {
        self.device = device
        _browser = State(initialValue: BrowserModel(serial: device.serial, adb: adb))
    }

    private var selectedFiles: [RemoteFile] {
        browser.files.filter { selection.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            PathBar(path: browser.path) { browser.navigate(to: $0) }
            Divider()
            fileTable
        }
        .navigationTitle(device.displayName)
        .navigationSubtitle(browser.path)
        .toolbar { toolbar }
        .searchable(text: $browser.searchText, placement: .toolbar, prompt: "Filter this folder")
        .task { await browser.reload() }
        .onChange(of: browser.path) { selection.removeAll() }
        .onChange(of: app.completedTransferTick) { Task { await browser.reload() } }
        .onChange(of: app.navigationRequest) {
            if let request = app.navigationRequest, request.serial == device.serial {
                browser.navigate(to: request.path)
            }
        }
        .alert("New Folder", isPresented: $showingNewFolder) {
            TextField("Name", text: $newFolderName)
            Button("Create") {
                let name = newFolderName
                perform { try await browser.makeDirectory(named: name) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let file = renaming {
                    let name = renameText
                    perform { try await browser.rename(file, to: name) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(deleteTitle, isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                let targets = pendingDelete
                perform { try await browser.delete(targets) }
            }
        } message: {
            Text("This permanently deletes the items from the device. It can't be undone.")
        }
    }

    // MARK: Table

    private var fileTable: some View {
        let files = browser.displayedFiles
        return Table(files, selection: $selection, sortOrder: $browser.sortOrder) {
            TableColumn("Name", value: \.name) { file in
                HStack(spacing: 8) {
                    Image(systemName: file.iconName)
                        .foregroundStyle(file.isDirectory ? Color.accentColor : .secondary)
                        .frame(width: 18)
                    Text(file.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .width(min: 220, ideal: 360)

            TableColumn("Size", value: \.size) { file in
                Text(file.isDirectory ? "--" : ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 90)

            TableColumn("Date Modified", value: \.modified) { file in
                Text(file.modified, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                    .foregroundStyle(.secondary)
            }
            .width(min: 130, ideal: 170)

            TableColumn("Kind", value: \.kind) { file in
                Text(file.kind)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 80, ideal: 130)
        }
        .contextMenu(forSelectionType: RemoteFile.ID.self) { ids in
            contextMenu(for: files.filter { ids.contains($0.id) })
        } primaryAction: { ids in
            let targets = files.filter { ids.contains($0.id) }
            if targets.count == 1, let only = targets.first {
                if only.isDirectory { browser.navigate(to: only.path) } else { app.open(only, serial: device.serial) }
            } else if !targets.isEmpty {
                downloadWithPanel(targets)
            }
        }
        .overlay { tableOverlay(isEmpty: files.isEmpty) }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.08)))
                    .overlay {
                        Label("Copy to \((browser.path as NSString).lastPathComponent)", systemImage: "square.and.arrow.down.on.square")
                            .font(.title3.weight(.medium))
                            .padding(12)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let fileURLs = urls.filter(\.isFileURL)
            guard !fileURLs.isEmpty else { return false }
            app.upload(fileURLs, to: browser.path, serial: device.serial)
            return true
        } isTargeted: { dropTargeted = $0 }
    }

    @ViewBuilder
    private func tableOverlay(isEmpty: Bool) -> some View {
        if let error = browser.errorMessage {
            ContentUnavailableView("Can't Open Folder", systemImage: "folder.badge.questionmark", description: Text(error))
        } else if isEmpty && browser.isLoading {
            ProgressView()
        } else if isEmpty && !browser.searchText.isEmpty {
            ContentUnavailableView.search(text: browser.searchText)
        } else if isEmpty {
            ContentUnavailableView("Folder Is Empty", systemImage: "folder",
                                   description: Text("Drag files from Finder here to copy them to your device."))
        }
    }

    @ViewBuilder
    private func contextMenu(for targets: [RemoteFile]) -> some View {
        if targets.isEmpty {
            Button("Upload Files…", action: uploadWithPanel)
            Button("New Folder…", action: promptNewFolder)
            Button("Refresh") { Task { await browser.reload() } }
        } else {
            if targets.count == 1, let only = targets.first {
                Button(only.isDirectory ? "Open" : "Open on Mac") {
                    if only.isDirectory { browser.navigate(to: only.path) } else { app.open(only, serial: device.serial) }
                }
                Divider()
            }
            Button("Download to Mac…") { downloadWithPanel(targets) }
            Button("Download to Downloads Folder") { download(targets, to: Panels.downloadsFolder) }
            if targets.count == 1, let only = targets.first {
                Button("Rename…") { startRename(only) }
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(targets.map(\.path).joined(separator: "\n"), forType: .string)
            }
            Divider()
            Button("Delete…", role: .destructive) { confirmDelete(targets) }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            ControlGroup {
                Button { browser.goBack() } label: { Label("Back", systemImage: "chevron.left") }
                    .disabled(!browser.canGoBack)
                    .keyboardShortcut("[", modifiers: .command)
                Button { browser.goForward() } label: { Label("Forward", systemImage: "chevron.right") }
                    .disabled(!browser.canGoForward)
                    .keyboardShortcut("]", modifiers: .command)
            }
            Button { browser.goUp() } label: { Label("Enclosing Folder", systemImage: "arrow.turn.left.up") }
                .disabled(!browser.canGoUp)
                .keyboardShortcut(.upArrow, modifiers: .command)
                .help("Go to enclosing folder")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: uploadWithPanel) { Label("Upload", systemImage: "square.and.arrow.up") }
                .help("Copy files from your Mac to this folder")
                .keyboardShortcut("u", modifiers: .command)
            Button { downloadWithPanel(selectedFiles) } label: { Label("Download", systemImage: "square.and.arrow.down") }
                .help("Copy the selected items to your Mac")
                .disabled(selection.isEmpty)
                .keyboardShortcut("d", modifiers: .command)
            Button(action: promptNewFolder) { Label("New Folder", systemImage: "folder.badge.plus") }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button { confirmDelete(selectedFiles) } label: { Label("Delete", systemImage: "trash") }
                .disabled(selection.isEmpty)
                .keyboardShortcut(.delete, modifiers: .command)
            Menu {
                Button("Install APK…", action: installWithPanel)
                Divider()
                Toggle("Show Hidden Files", isOn: $browser.showHidden)
                Button("Refresh") { Task { await browser.reload() } }
                    .keyboardShortcut("r", modifiers: .command)
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    }

    // MARK: Actions

    private var deleteTitle: String {
        pendingDelete.count == 1 ? "Delete “\(pendingDelete[0].name)”?" : "Delete \(pendingDelete.count) items?"
    }

    private func uploadWithPanel() {
        let urls = Panels.chooseFilesToUpload()
        guard !urls.isEmpty else { return }
        app.upload(urls, to: browser.path, serial: device.serial)
    }

    private func installWithPanel() {
        let apks = Panels.chooseAPKs()
        if !apks.isEmpty { app.install(apks, serial: device.serial) }
    }

    private func downloadWithPanel(_ targets: [RemoteFile]) {
        guard !targets.isEmpty, let folder = Panels.chooseDownloadFolder() else { return }
        download(targets, to: folder)
    }

    private func download(_ targets: [RemoteFile], to folder: URL) {
        app.download(targets, to: folder, serial: device.serial)
    }

    private func promptNewFolder() {
        newFolderName = "New Folder"
        showingNewFolder = true
    }

    private func startRename(_ file: RemoteFile) {
        renameText = file.name
        renaming = file
    }

    private func confirmDelete(_ targets: [RemoteFile]) {
        guard !targets.isEmpty else { return }
        pendingDelete = targets
        showingDeleteConfirm = true
    }

    private func perform(_ operation: @escaping () async throws -> Void) {
        Task {
            do { try await operation() } catch { app.alertMessage = error.localizedDescription }
        }
    }
}

struct PathBar: View {
    let path: String
    let onSelect: (String) -> Void

    private var crumbs: [(title: String, path: String)] {
        var result: [(String, String)]
        var remainder: String
        if path == "/sdcard" || path.hasPrefix("/sdcard/") {
            result = [("Internal Storage", "/sdcard")]
            remainder = String(path.dropFirst("/sdcard".count))
        } else {
            result = [("Device", "/")]
            remainder = path
        }
        var current = result[0].1
        for component in remainder.split(separator: "/") {
            current = RemotePath.join(current, String(component))
            result.append((String(component), current))
        }
        return result
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                let items = crumbs
                ForEach(Array(items.enumerated()), id: \.offset) { index, crumb in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    Button {
                        onSelect(crumb.path)
                    } label: {
                        HStack(spacing: 4) {
                            if index == 0 { Image(systemName: "internaldrive") }
                            Text(crumb.title)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(index == items.count - 1 ? .primary : .secondary)
                    .fontWeight(index == items.count - 1 ? .semibold : .regular)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(.bar)
    }
}
