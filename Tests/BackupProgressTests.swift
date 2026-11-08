import Foundation

@main
struct BackupProgressTests {
    static func main() throws {
        var time = 0.0
        var estimate = BackupProgress()
        let tracker = BackupProgressTracker(emit: { estimate = $0 }, clock: { time })
        tracker.plan([(URL(fileURLWithPath: "/fixture"), 100)])
        tracker.begin(URL(fileURLWithPath: "/fixture"), size: 100)
        time = 1
        tracker.advance(0.2)
        precondition(abs(estimate.secondsRemaining! - 4) < 0.001)
        tracker.phase(.copying)
        time = 2
        tracker.copiedChunk(50, fileBytes: 50)
        precondition(estimate.bytesPerSecond == 50 && abs(estimate.secondsRemaining! - 2) < 0.001)
        tracker.phase(.verifyingCopy)
        precondition(estimate.bytesPerSecond == 0)
        time = 3
        tracker.advance(0.8)
        precondition(abs(estimate.secondsRemaining! - 0.75) < 0.001)
        tracker.finish(cancelled: false, report: BackupReport())
        precondition(estimate.secondsRemaining == 0 && estimate.percentage == 100)
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: base) }
        let source = base.appendingPathComponent("source")
        let destination = base.appendingPathComponent("destination")
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        let file = source.appendingPathComponent("large.bin")
        let data = Data(repeating: 0x5a, count: 12 * 1024 * 1024)
        try data.write(to: file)
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        try fm.setAttributes([.modificationDate: timestamp, .posixPermissions: 0o640], ofItemAtPath: file.path)
        var events: [BackupProgress] = []
        let report = try BackupEngine().run(source: source, destination: destination, folder: "Verified", checkOnly: false, telemetry: { events.append($0) }, progress: { _ in })
        precondition(report.copied == 1 && report.errors.isEmpty)
        precondition(events.contains { $0.phase == .copying && $0.currentFileTransferred > 0 && $0.bytesPerSecond > 0 })
        precondition(events.contains { $0.phase == .verifyingCopy } && events.contains { $0.phase == .verifyingSource })
        precondition(events.last!.phase == .finished && events.last!.fraction == 1)
        precondition(events.last!.totalBytes == Int64(data.count) && events.last!.transferredBytes == Int64(data.count))
        precondition(events.last!.processedFiles == 1 && events.last!.copied == 1)
        for (a, b) in zip(events, events.dropFirst()) { precondition(b.fraction >= a.fraction && b.fraction <= 1) }
        precondition(events.filter { $0.phase != .finished }.allSatisfy { $0.percentage < 100 })
        let target = destination.appendingPathComponent("Verified/large.bin")
        precondition(tryData(target) == data)
        let attributes = try fm.attributesOfItem(atPath: target.path)
        precondition(abs((attributes[.modificationDate] as! Date).timeIntervalSince(timestamp)) < 1)
        precondition((attributes[.posixPermissions] as! NSNumber).intValue == 0o640)
        events = []
        let repeated = try BackupEngine().run(source: source, destination: destination, folder: "Verified", checkOnly: false, telemetry: { events.append($0) }, progress: { _ in })
        precondition(repeated.copied == 0 && repeated.existing == 1 && events.last!.transferredBytes == 0)
        precondition(events.last!.existing == 1 && events.last!.percentage == 100)
        let engine = BackupEngine()
        events = []
        let stopped = try engine.run(source: source, destination: destination, folder: "Stopped", checkOnly: false, telemetry: { event in
            events.append(event)
            if event.phase == .copying && event.currentFileTransferred > 0 { engine.cancel() }
        }, progress: { _ in })
        precondition(stopped.copied == 0 && events.last!.phase == .stopped && events.last!.fraction < 1)
        precondition(events.last!.transferredBytes > 0 && events.last!.transferredBytes < Int64(data.count))
        precondition(!fm.fileExists(atPath: destination.appendingPathComponent("Stopped/large.bin").path))
        let leftovers = try fm.contentsOfDirectory(atPath: destination.appendingPathComponent("Stopped").path)
        precondition(leftovers.isEmpty)
        precondition(tryData(file) == data)
        let emptySource = base.appendingPathComponent("empty")
        try fm.createDirectory(at: emptySource, withIntermediateDirectories: true)
        try Data().write(to: emptySource.appendingPathComponent("empty.txt"))
        events = []
        let empty = try BackupEngine().run(source: emptySource, destination: destination, folder: "Empty", checkOnly: false, telemetry: { events.append($0) }, progress: { _ in })
        precondition(empty.copied == 1 && events.last!.fraction == 1 && events.last!.totalBytes == 0)
        precondition(events.allSatisfy { $0.fraction.isFinite && $0.bytesPerSecond.isFinite && ($0.secondsRemaining?.isFinite ?? true) })
        events = []
        let changed = try BackupEngine().run(source: emptySource, destination: destination, folder: "Changed", checkOnly: false, telemetry: { event in
            events.append(event)
            if event.phase == .verifyingSource { try! Data("changed".utf8).write(to: emptySource.appendingPathComponent("empty.txt")) }
        }, progress: { _ in })
        precondition(changed.copied == 0 && changed.errors.count == 1 && events.last!.issues == 1)
        precondition(!fm.fileExists(atPath: destination.appendingPathComponent("Changed/empty.txt").path))
        print("PASS: live chunk progress, nondecreasing percentage, verification stages, accurate transferred bytes, speed, preserved timestamps/permissions, duplicate skip, mid-file cancellation and partial cleanup, zero-byte files, source-change detection")
    }
    static func tryData(_ url: URL) -> Data { try! Data(contentsOf: url) }
}
