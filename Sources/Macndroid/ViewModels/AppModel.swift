import AppKit
import Foundation
import Observation

struct NavigationRequest: Equatable {
    let id = UUID()
    let serial: String
    let path: String
}

@MainActor
@Observable
final class AppModel {
    private(set) var adb: ADBClient?
    var devices: [Device] = []
    var selectedSerial: String?
    var transfers: [TransferItem] = []
    /// Incremented whenever a transfer finishes, so browsers can refresh.
    private(set) var completedTransferTick = 0
    var navigationRequest: NavigationRequest?
    var alertMessage: String?
    private(set) var hasPolledOnce = false

    @ObservationIgnored private var detailsCache: [String: DeviceDetails] = [:]
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var queueRunning = false

    init() {
        adb = ADBClient.locate()
    }

    var selectedDevice: Device? {
        devices.first { $0.serial == selectedSerial }
    }

    var hasActiveTransfers: Bool {
        transfers.contains { !$0.status.isFinished }
    }

    // MARK: - Devices

    func start() {
        guard pollTask == nil, let adb else { return }
        pollTask = Task { [weak self] in
            await adb.startServer()
            while !Task.isCancelled {
                await self?.refreshDevices()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func retryLocatingADB() {
        adb = ADBClient.locate()
        start()
    }

    func refreshDevices() async {
        guard let adb, let result = try? await adb.run(["devices", "-l"]) else { return }
        var parsed = Device.parseList(result.stdout)

        for index in parsed.indices where parsed[index].state == .device {
            let serial = parsed[index].serial
            if detailsCache[serial] == nil {
                detailsCache[serial] = await fetchDetails(serial: serial)
            }
            parsed[index].details = detailsCache[serial]
        }
        let connected = Set(parsed.map(\.serial))
        detailsCache = detailsCache.filter { connected.contains($0.key) }

        if parsed != devices { devices = parsed }
        if selectedSerial == nil || !connected.contains(selectedSerial!) {
            selectedSerial = parsed.first(where: { $0.state == .device })?.serial ?? parsed.first?.serial
        }
        hasPolledOnce = true
    }

    private func fetchDetails(serial: String) async -> DeviceDetails? {
        guard let adb else { return nil }
        let command = [
            "getprop ro.product.manufacturer",
            "getprop ro.product.model",
            "getprop ro.build.version.release",
            "getprop ro.build.characteristics",
            "df -k /sdcard/ | tail -n 1",
        ].joined(separator: "; ")
        guard let result = try? await adb.shell(serial, command), result.succeeded else { return nil }

        let lines = result.stdout.components(separatedBy: "\n").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func line(_ i: Int) -> String? { i < lines.count && !lines[i].isEmpty ? lines[i] : nil }

        var details = DeviceDetails(
            manufacturer: line(0),
            model: line(1),
            androidVersion: line(2),
            isTablet: line(3)?.contains("tablet") ?? false
        )
        // df: Filesystem 1K-blocks Used Available Use% Mounted-on
        if let df = line(4) {
            let cols = df.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if cols.count >= 4, let total = Int64(cols[1]), let free = Int64(cols[3]) {
                details.storageTotal = total * 1024
                details.storageFree = free * 1024
            }
        }
        return details
    }

    func requestNavigation(serial: String, path: String) {
        navigationRequest = NavigationRequest(serial: serial, path: path)
    }

    // MARK: - Wi‑Fi

    func connect(address: String) async {
        guard let adb else { return }
        var target = address.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return }
        if !target.contains(":") { target += ":5555" }
        let result = try? await adb.run(["connect", target])
        let output = (result?.stdout ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !output.contains("connected to") {
            alertMessage = output.isEmpty ? "Couldn't connect to \(target)." : output
        }
        await refreshDevices()
    }

    func pair(address: String, code: String) async {
        guard let adb else { return }
        let result = try? await adb.run(["pair", address.trimmingCharacters(in: .whitespaces),
                                         code.trimmingCharacters(in: .whitespaces)])
        let output = ((result?.stdout ?? "") + (result?.stderr ?? "")).trimmingCharacters(in: .whitespacesAndNewlines)
        alertMessage = output.isEmpty ? "Pairing finished." : output
    }

    /// Switches a USB-connected device to wireless adb on port 5555.
    func switchToWiFi(_ device: Device) async {
        guard let adb else { return }
        let info = try? await adb.shell(device.serial, "ip -f inet addr show wlan0")
        guard let ip = Self.parseIPv4(info?.stdout ?? "") else {
            alertMessage = "Couldn't find the device's Wi‑Fi address. Make sure Wi‑Fi is on and the device is on the same network as this Mac."
            return
        }
        _ = try? await adb.run(["-s", device.serial, "tcpip", "5555"])
        try? await Task.sleep(for: .seconds(2))
        await connect(address: "\(ip):5555")
    }

    func disconnect(_ device: Device) async {
        guard let adb else { return }
        _ = try? await adb.run(["disconnect", device.serial])
        await refreshDevices()
    }

    private static func parseIPv4(_ text: String) -> String? {
        guard let range = text.range(of: "inet ") else { return nil }
        let rest = text[range.upperBound...]
        let ip = rest.prefix { $0.isNumber || $0 == "." }
        return ip.isEmpty ? nil : String(ip)
    }

    // MARK: - Transfers

    func upload(_ urls: [URL], to remoteDirectory: String, serial: String) {
        let items = urls.map { url -> TransferItem in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            let isDir = values?.isDirectory ?? false
            return TransferItem(kind: .upload, name: url.lastPathComponent, serial: serial,
                                source: url.path, destination: remoteDirectory, isDirectory: isDir,
                                totalBytes: isDir ? nil : values?.fileSize.map(Int64.init))
        }
        enqueue(items)
    }

    func download(_ files: [RemoteFile], to localDirectory: URL, serial: String, openWhenDone: Bool = false) {
        let items = files.map {
            TransferItem(kind: .download, name: $0.name, serial: serial, source: $0.path,
                         destination: localDirectory.path, isDirectory: $0.isDirectory,
                         totalBytes: $0.isDirectory ? nil : $0.size, openWhenDone: openWhenDone)
        }
        enqueue(items)
    }

    /// Copies a file to a temp folder and opens it with the default Mac app.
    func open(_ file: RemoteFile, serial: String) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Macndroid-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        download([file], to: dir, serial: serial, openWhenDone: true)
    }

    func install(_ apks: [URL], serial: String) {
        let items = apks.map { url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init)
            return TransferItem(kind: .install, name: url.lastPathComponent, serial: serial,
                                source: url.path, destination: "", isDirectory: false, totalBytes: size)
        }
        enqueue(items)
    }

    func cancel(_ item: TransferItem) {
        switch item.status {
        case .queued: item.status = .cancelled
        case .running: item.handle.cancel()
        default: break
        }
    }

    func clearFinished() {
        transfers.removeAll { $0.status.isFinished }
    }

    private func enqueue(_ items: [TransferItem]) {
        guard !items.isEmpty else { return }
        transfers.append(contentsOf: items)
        guard !queueRunning else { return }
        queueRunning = true
        Task {
            while let next = transfers.first(where: { $0.status == .queued }) {
                await perform(next)
            }
            queueRunning = false
        }
    }

    private func perform(_ item: TransferItem) async {
        guard let adb else {
            item.status = .failed("adb not found")
            return
        }
        item.status = .running
        item.startedAt = Date()

        let args: [String]
        switch item.kind {
        case .upload:
            // Trailing slash: adb places the file/folder inside the destination folder.
            args = ["-s", item.serial, "push", item.source, item.destination.hasSuffix("/") ? item.destination : item.destination + "/"]
        case .download:
            args = ["-s", item.serial, "pull", item.source, item.destination]
        case .install:
            args = ["-s", item.serial, "install", "-r", item.source]
        }

        let monitor = Task { [weak self] in await self?.monitorProgress(item) }
        let result: CommandResult?
        var thrown: Error?
        do { result = try await adb.run(args, handle: item.handle) } catch { result = nil; thrown = error }
        monitor.cancel()
        item.finishedAt = Date()

        if item.handle.isCancelled {
            item.status = .cancelled
        } else if let result, result.succeeded,
                  item.kind != .install || result.stdout.contains("Success") {
            if let total = item.totalBytes { item.transferredBytes = total }
            item.status = .completed
            if item.openWhenDone {
                NSWorkspace.shared.open(URL(fileURLWithPath: item.targetPath))
            }
        } else if let result {
            item.status = .failed(result.errorSummary)
        } else {
            item.status = .failed(thrown?.localizedDescription ?? "Unknown error")
        }

        if item.kind == .upload || item.kind == .install {
            detailsCache[item.serial] = nil  // refresh storage numbers on next poll
        }
        completedTransferTick += 1
    }

    /// Polls the size of the file being written to show real progress.
    private func monitorProgress(_ item: TransferItem) async {
        guard let adb, !item.isDirectory, item.kind != .install else { return }
        let target = item.targetPath
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(700))
            if Task.isCancelled { return }
            switch item.kind {
            case .upload:
                if let r = try? await adb.shell(item.serial, "stat -c %s \(target.shellQuoted) 2>/dev/null"),
                   let size = Int64(r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)),
                   !Task.isCancelled {
                    item.transferredBytes = size
                }
            case .download:
                if let attrs = try? FileManager.default.attributesOfItem(atPath: target),
                   let size = attrs[.size] as? NSNumber {
                    item.transferredBytes = size.int64Value
                }
            case .install:
                return
            }
        }
    }
}
