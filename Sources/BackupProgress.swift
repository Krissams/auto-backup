import Foundation

enum BackupPhase: String {
    case preparing = "Preparing files"
    case readingSource = "Reading source"
    case checkingExisting = "Checking existing copies"
    case copying = "Transferring file"
    case verifyingCopy = "Verifying copied file"
    case verifyingSource = "Confirming source is unchanged"
    case finished = "Finished"
    case stopped = "Stopped"
    case failed = "Couldn’t finish"
}

struct BackupProgress {
    var phase: BackupPhase = .preparing
    var fraction = 0.0
    var totalFiles = 0
    var processedFiles = 0
    var totalBytes: Int64 = 0
    var transferredBytes: Int64 = 0
    var currentFile: String?
    var currentFileBytes: Int64 = 0
    var currentFileTransferred: Int64 = 0
    var bytesPerSecond = 0.0
    var secondsRemaining: Double?
    var elapsedSeconds = 0.0
    var copied = 0
    var existing = 0
    var issues = 0
    var percentage: Int { min(100, max(0, Int((fraction * 100).rounded(.down)))) }
}

struct TransferSpeedSample {
    let elapsed: Double
    let bytesPerSecond: Double
}

// Owned by one background run. Uses monotonic time and throttles updates to the UI.
final class BackupProgressTracker {
    private(set) var snapshot = BackupProgress()
    private let emit: ((BackupProgress) -> Void)?
    private let clock: () -> Double
    private let started: Double
    private var lastEmission = -Double.infinity
    private var totalWork = 0.0
    private var completedWork = 0.0
    private var fileWeight = 0.0
    private var fileFraction = 0.0
    private var copyStarted = 0.0
    private var copyDuration = 0.0

    init(emit: ((BackupProgress) -> Void)?, clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.emit = emit
        self.clock = clock
        self.started = clock()
        publish(force: true)
    }
    func plan(_ files: [(URL, Int64)]) {
        snapshot.totalFiles = files.count
        snapshot.totalBytes = files.reduce(0) { $0 + $1.1 }
        totalWork = files.reduce(0) { $0 + Double(max(1, $1.1)) }
        publish(force: true)
    }
    func begin(_ url: URL, size: Int64) {
        fileWeight = Double(max(1, size))
        fileFraction = 0
        snapshot.currentFile = url.path
        snapshot.currentFileBytes = size
        snapshot.currentFileTransferred = 0
        phase(.readingSource)
    }
    func phase(_ phase: BackupPhase) {
        snapshot.phase = phase
        snapshot.bytesPerSecond = 0
        if phase == .copying { copyStarted = clock(); copyDuration = 0 }
        publish(force: true)
    }
    func advance(_ fraction: Double) {
        fileFraction = max(fileFraction, min(1, max(0, fraction)))
        let value = totalWork > 0 ? (completedWork + fileWeight * fileFraction) / totalWork : 0
        // Reserve 100% for the final result after all files are safely finalized.
        snapshot.fraction = min(0.999, max(snapshot.fraction, value))
        publish()
    }
    func copiedChunk(_ count: Int, fileBytes: Int64) {
        snapshot.transferredBytes += Int64(count)
        snapshot.currentFileTransferred = fileBytes
        copyDuration = max(0.001, clock() - copyStarted)
        snapshot.bytesPerSecond = Double(fileBytes) / copyDuration
        let part = snapshot.currentFileBytes > 0 ? min(1, Double(fileBytes) / Double(snapshot.currentFileBytes)) : 1
        advance(0.4 + part * 0.2)
        publish(force: fileBytes == Int64(count))
    }
    func completeFile(report: BackupReport) {
        completedWork += fileWeight
        fileWeight = 0
        snapshot.processedFiles += 1
        snapshot.copied = report.copied
        snapshot.existing = report.existing
        snapshot.issues = report.errors.count
        advance(0)
        publish(force: true)
    }
    func finish(cancelled: Bool, report: BackupReport) {
        snapshot.phase = cancelled ? .stopped : .finished
        if !cancelled { snapshot.fraction = 1 }
        snapshot.bytesPerSecond = 0
        snapshot.copied = report.copied
        snapshot.existing = report.existing
        snapshot.issues = report.errors.count
        snapshot.secondsRemaining = cancelled ? nil : 0
        publish(force: true)
    }
    private func publish(force: Bool = false) {
        let now = clock()
        guard force || now - lastEmission >= 0.15 else { return }
        snapshot.elapsedSeconds = max(0, now - started)
        if snapshot.phase != .finished && snapshot.phase != .stopped {
            let done = completedWork + fileWeight * fileFraction
            snapshot.secondsRemaining = done > 0 && snapshot.elapsedSeconds >= 0.5
                ? max(0, (totalWork - done) / (done / snapshot.elapsedSeconds)) : nil
        }
        lastEmission = now
        emit?(snapshot)
    }
}
