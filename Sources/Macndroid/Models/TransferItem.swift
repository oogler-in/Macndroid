import Foundation
import Observation

@Observable
final class TransferItem: Identifiable {
    enum Kind { case upload, download, install }

    enum Status: Equatable {
        case queued, running, completed, failed(String), cancelled

        var isFinished: Bool {
            switch self {
            case .completed, .failed, .cancelled: return true
            default: return false
            }
        }
    }

    let id = UUID()
    let kind: Kind
    let name: String
    let serial: String
    /// Local path for uploads/installs, remote path for downloads.
    let source: String
    /// Remote folder for uploads, local folder for downloads.
    let destination: String
    let isDirectory: Bool
    let openWhenDone: Bool

    var totalBytes: Int64?
    var transferredBytes: Int64 = 0
    var status: Status = .queued
    var startedAt: Date?
    var finishedAt: Date?

    @ObservationIgnored let handle = ProcessHandle()

    init(kind: Kind, name: String, serial: String, source: String, destination: String,
         isDirectory: Bool, totalBytes: Int64?, openWhenDone: Bool = false) {
        self.kind = kind
        self.name = name
        self.serial = serial
        self.source = source
        self.destination = destination
        self.isDirectory = isDirectory
        self.totalBytes = totalBytes
        self.openWhenDone = openWhenDone
    }

    /// Where the finished file ends up.
    var targetPath: String {
        switch kind {
        case .upload: return RemotePath.join(destination, name)
        case .download: return (destination as NSString).appendingPathComponent(name)
        case .install: return source
        }
    }

    var fraction: Double? {
        guard let total = totalBytes, total > 0, status == .running || status == .completed else { return nil }
        return min(1, Double(transferredBytes) / Double(total))
    }

    var bytesPerSecond: Double? {
        guard let startedAt, transferredBytes > 0 else { return nil }
        let elapsed = (finishedAt ?? Date()).timeIntervalSince(startedAt)
        return elapsed > 0.5 ? Double(transferredBytes) / elapsed : nil
    }
}
