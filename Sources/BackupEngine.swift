import Foundation
import CryptoKit
import Darwin

struct BackupReport {
    var copied = 0
    var existing = 0
    var pending = 0
    var excluded = 0
    var errors: [String] = []
}

enum BackupFailure: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

// A run owns its local state; cancellation is the only shared mutation and is locked.
final class BackupEngine: @unchecked Sendable {
    private let fm = FileManager.default
    private let lock = NSLock()
    private var stopped = false
    func cancel() { lock.lock(); stopped = true; lock.unlock() }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }

    func digest(_ url: URL, readProgress: ((Int64) -> Void)? = nil) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        var bytes: Int64 = 0
        while let data = try file.read(upToCount: 1024 * 1024), !data.isEmpty {
            if cancelled { throw BackupFailure.invalid("Cancelled") }
            hash.update(data: data)
            bytes += Int64(data.count)
            readProgress?(bytes)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func inside(_ child: URL, _ parent: URL) -> Bool {
        child.path == parent.path || child.path.hasPrefix(parent.path + "/")
    }

    func validate(source: URL, destination: URL, folder: String) throws -> (URL, URL) {
        let name = folder.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0") else {
            throw BackupFailure.invalid("Enter a folder name without slashes.")
        }
        let source = source.standardizedFileURL.resolvingSymlinksInPath()
        let destination = destination.standardizedFileURL.resolvingSymlinksInPath()
        for url in [source, destination] {
            var directory: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue else {
                throw BackupFailure.invalid("Folder unavailable: \(url.path). Reconnect the drive and try again.")
            }
        }
        let target = destination.appendingPathComponent(name, isDirectory: true)
        guard !inside(target.resolvingSymlinksInPath(), source), !inside(source, target.resolvingSymlinksInPath()) else {
            throw BackupFailure.invalid("Source and backup folders must not overlap.")
        }
        return (source, target)
    }

    // Reject destination symlinks so an existing folder cannot redirect writes elsewhere.
    private func safePath(_ url: URL, root: URL) throws {
        var current = url.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        while current == rootPath || current.hasPrefix(rootPath + "/") {
            if let attrs = try? fm.attributesOfItem(atPath: current), attrs[.type] as? FileAttributeType == .typeSymbolicLink {
                throw BackupFailure.invalid("Symbolic link in destination: \(current)")
            }
            if current == rootPath { break }
            current = (current as NSString).deletingLastPathComponent
        }
    }

    private func copyFile(_ source: URL, to target: URL, progress: (Int, Int64) -> Void) throws {
        guard fm.createFile(atPath: target.path, contents: nil) else {
            throw BackupFailure.invalid("Cannot create the backup file.")
        }
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let output = try FileHandle(forWritingTo: target)
        defer { try? output.close() }
        var written: Int64 = 0
        while let data = try input.read(upToCount: 4 * 1024 * 1024), !data.isEmpty {
            if cancelled { throw BackupFailure.invalid("Cancelled") }
            try output.write(contentsOf: data)
            written += Int64(data.count)
            progress(data.count, written)
        }
        try output.synchronize()
        // Preserve permissions, timestamps, extended attributes and resource forks.
        guard copyfile(source.path, target.path, nil, copyfile_flags_t(COPYFILE_METADATA)) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: target.path])
        }
    }

    func run(source: URL, destination: URL, folder: String, checkOnly: Bool, selectedPaths: Set<String>? = nil,
             telemetry: ((BackupProgress) -> Void)? = nil,
             progress: @escaping (String) -> Void) throws -> BackupReport {
        let tracker = BackupProgressTracker(emit: telemetry)
        let (source, root) = try validate(source: source, destination: destination, folder: folder)
        try safePath(root, root: root)
        var report = BackupReport()
        var files: [(URL, Int64)] = []
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let enumerator = fm.enumerator(at: source, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { url, error in
            report.errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            return true
        }) else { throw BackupFailure.invalid("Cannot read the source folder.") }
        for case let file as URL in enumerator {
            if cancelled { break }
            do {
                let values = try file.resourceValues(forKeys: keys)
                if values.isSymbolicLink == true { report.excluded += 1; continue }
                guard values.isRegularFile == true else { continue }
                let canonical = file.standardizedFileURL.resolvingSymlinksInPath()
                guard canonical.path.hasPrefix(source.path + "/") else {
                    throw BackupFailure.invalid("File resolved outside the source folder.")
                }
                if let selectedPaths, !selectedPaths.contains(canonical.path) { continue }
                guard let size = values.fileSize else { throw BackupFailure.invalid("Cannot read file size.") }
                files.append((canonical, Int64(size)))
            } catch { report.errors.append("\(file.path): \(error.localizedDescription)") }
        }
        tracker.plan(files)
        for (file, size) in files {
            if cancelled { break }
            let relative = String(file.path.dropFirst(source.path.count + 1))
            tracker.begin(file, size: size)
            defer { if !cancelled { tracker.completeFile(report: report) } }
            let fraction: (Int64) -> Double = { size > 0 ? min(1, Double($0) / Double(size)) : 1 }
            do {
                progress("\(checkOnly ? "Checking" : "Backing up") · \(relative)")
                let sourceHash = try digest(file) { tracker.advance(fraction($0) * 0.2) }
                tracker.advance(0.2)
                tracker.phase(.checkingExisting)
                func matches(_ target: URL) -> Bool {
                    (try? digest(target) { tracker.advance(0.2 + fraction($0) * 0.2) }) == sourceHash
                }
                var target = root.appendingPathComponent(relative)
                try safePath(target, root: root)
                if fm.fileExists(atPath: target.path) {
                    if matches(target) { report.existing += 1; continue }
                    let ext = target.pathExtension
                    let stem = target.deletingPathExtension().lastPathComponent
                    let parent = target.deletingLastPathComponent()
                    let suffix = ext.isEmpty ? "" : "." + ext
                    var number = 0
                    repeat {
                        if cancelled { throw BackupFailure.invalid("Cancelled") }
                        let extra = number == 0 ? "" : "-\(number)"
                        target = parent.appendingPathComponent("\(stem) (\(sourceHash.prefix(12))\(extra))\(suffix)")
                        try safePath(target, root: root)
                        if !fm.fileExists(atPath: target.path) { break }
                        if matches(target) { break }
                        number += 1
                    } while true
                    if fm.fileExists(atPath: target.path) { report.existing += 1; continue }
                }
                if checkOnly { report.pending += 1; continue }
                if cancelled { break }
                tracker.advance(0.4)
                let parent = target.deletingLastPathComponent()
                try fm.createDirectory(at: parent, withIntermediateDirectories: true)
                try safePath(target, root: root)
                let temporary = parent.appendingPathComponent(".autobackup-\(UUID().uuidString).partial")
                defer { try? fm.removeItem(at: temporary) }
                tracker.phase(.copying)
                try copyFile(file, to: temporary) { count, written in tracker.copiedChunk(count, fileBytes: written) }
                tracker.advance(0.6)
                tracker.phase(.verifyingCopy)
                guard try digest(temporary, readProgress: { tracker.advance(0.6 + fraction($0) * 0.2) }) == sourceHash else {
                    throw BackupFailure.invalid("Copied file verification failed. Try again.")
                }
                tracker.advance(0.8)
                tracker.phase(.verifyingSource)
                guard try digest(file, readProgress: { tracker.advance(0.8 + fraction($0) * 0.2) }) == sourceHash else {
                    throw BackupFailure.invalid("File changed during backup. Try again.")
                }
                if cancelled { break }
                try fm.moveItem(at: temporary, to: target)
                report.copied += 1
            } catch {
                if cancelled { break }
                report.errors.append("\(relative): \(error.localizedDescription)")
            }
        }
        tracker.finish(cancelled: cancelled, report: report)
        return report
    }
}
