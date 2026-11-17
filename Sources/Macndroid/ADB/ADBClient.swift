import Foundation

struct ADBError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct CommandResult {
    let status: Int32
    let stdout: String
    let stderr: String
    var succeeded: Bool { status == 0 }

    /// Best human-readable error line from a failed adb command.
    var errorSummary: String {
        let text = stderr.isEmpty ? stdout : stderr
        let line = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last(where: { !$0.isEmpty }) ?? "Unknown error (exit code \(status))"
        return line
            .replacingOccurrences(of: "adb: error: ", with: "")
            .replacingOccurrences(of: "adb: ", with: "")
    }
}

/// Lets a caller cancel a running adb process (e.g. a transfer).
final class ProcessHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func attach(_ process: Process) {
        lock.lock()
        self.process = process
        let alreadyCancelled = cancelled
        lock.unlock()
        if alreadyCancelled { process.terminate() }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let process = self.process
        lock.unlock()
        if let process, process.isRunning { process.terminate() }
    }

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}

extension String {
    /// Quotes a string for safe use inside a remote `sh` command.
    var shellQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// Thin async wrapper around the `adb` command-line tool.
struct ADBClient: Sendable {
    let executableURL: URL

    /// Finds an adb binary: bundled in the app, Android SDK, Homebrew, or PATH.
    static func locate() -> ADBClient? {
        let env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var candidates: [String] = []

        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("platform-tools/adb").path)
        }
        for key in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
            if let sdk = env[key] { candidates.append("\(sdk)/platform-tools/adb") }
        }
        candidates += [
            "\(home)/Library/Android/sdk/platform-tools/adb",
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
        ]
        if let path = env["PATH"] {
            candidates += path.split(separator: ":").map { "\($0)/adb" }
        }

        let fm = FileManager.default
        guard let found = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) else { return nil }
        return ADBClient(executableURL: URL(fileURLWithPath: found))
    }

    /// Starts the adb server with output discarded (the daemon must not inherit our pipes).
    func startServer() async {
        let url = executableURL
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = url
                process.arguments = ["start-server"]
                process.standardInput = FileHandle.nullDevice
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                try? process.run()
                process.waitUntilExit()
                continuation.resume()
            }
        }
    }

    func run(_ arguments: [String], handle: ProcessHandle? = nil) async throws -> CommandResult {
        let url = executableURL
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = url
                process.arguments = arguments
                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardInput = FileHandle.nullDevice
                process.standardOutput = outPipe
                process.standardError = errPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: ADBError(message: "Couldn't run adb: \(error.localizedDescription)"))
                    return
                }
                handle?.attach(process)

                // Drain both pipes concurrently so large outputs never deadlock.
                let errBox = DataBox()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global(qos: .utility).async {
                    errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                process.waitUntilExit()

                continuation.resume(returning: CommandResult(
                    status: process.terminationStatus,
                    stdout: String(decoding: outData, as: UTF8.self),
                    stderr: String(decoding: errBox.data, as: UTF8.self)
                ))
            }
        }
    }

    func shell(_ serial: String, _ command: String) async throws -> CommandResult {
        try await run(["-s", serial, "shell", command])
    }
}
