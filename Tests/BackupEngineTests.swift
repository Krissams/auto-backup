import Foundation

@main
struct BackupEngineTests {
    static func main() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: base) }
        let source = base.appendingPathComponent("source")
        let destination = base.appendingPathComponent("destination")
        try fm.createDirectory(at: source.appendingPathComponent("nested"), withIntermediateDirectories: true)
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        let original = source.appendingPathComponent("nested/photo.txt")
        try Data("original".utf8).write(to: original)
        func run(_ check: Bool = false) throws -> BackupReport {
            try BackupEngine().run(source: source, destination: destination, folder: "Backup", checkOnly: check, progress: { _ in })
        }
        let preview = try run(true)
        precondition(preview.pending == 1 && preview.copied == 0)
        precondition(!fm.fileExists(atPath: destination.appendingPathComponent("Backup").path))
        let first = try run()
        precondition(first.copied == 1 && first.errors.isEmpty)
        let repeatRun = try run()
        precondition(repeatRun.existing == 1 && repeatRun.copied == 0)
        try Data("modified".utf8).write(to: original)
        let changed = try run()
        precondition(changed.copied == 1 && changed.errors.isEmpty)
        let backup = destination.appendingPathComponent("Backup/nested/photo.txt")
        let preserved = try String(contentsOf: backup, encoding: .utf8)
        precondition(preserved == "original")
        let again = try run()
        precondition(again.existing == 1 && again.copied == 0)
        try fm.createSymbolicLink(at: source.appendingPathComponent("link"), withDestinationURL: original)
        let links = try run()
        precondition(links.excluded == 1)
        do {
            _ = try BackupEngine().validate(source: source, destination: source, folder: "inside")
            fatalError("Overlapping folders accepted")
        } catch is BackupFailure {}
        do {
            _ = try BackupEngine().validate(source: source, destination: destination, folder: "../escape")
            fatalError("Traversal accepted")
        } catch is BackupFailure {}
        let outside = base.appendingPathComponent("outside")
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: destination.appendingPathComponent("Redirect"), withDestinationURL: outside)
        do {
            _ = try BackupEngine().run(source: source, destination: destination, folder: "Redirect", checkOnly: false, progress: { _ in })
            fatalError("Destination symlink accepted")
        } catch is BackupFailure {}
        let stopped = BackupEngine()
        stopped.cancel()
        let cancelled = try stopped.run(source: source, destination: destination, folder: "Cancelled", checkOnly: false, progress: { _ in })
        precondition(cancelled.copied == 0)
        let sourceContents = try String(contentsOf: original, encoding: .utf8)
        precondition(sourceContents == "modified")
        let unwanted = source.appendingPathComponent("leave-out.txt")
        try Data("do not copy".utf8).write(to: unwanted)
        let selectedPaths: Set<String> = [original.standardizedFileURL.resolvingSymlinksInPath().path]
        let selected = try BackupEngine().run(source: source, destination: destination, folder: "Selected", checkOnly: false, selectedPaths: selectedPaths, progress: { _ in })
        precondition(selected.copied == 1 && selected.errors.isEmpty)
        precondition(fm.fileExists(atPath: destination.appendingPathComponent("Selected/nested/photo.txt").path))
        precondition(!fm.fileExists(atPath: destination.appendingPathComponent("Selected/leave-out.txt").path))
        try Data("new since review".utf8).write(to: source.appendingPathComponent("new.txt"))
        let selectedRepeat = try BackupEngine().run(source: source, destination: destination, folder: "Selected", checkOnly: false, selectedPaths: selectedPaths, progress: { _ in })
        precondition(selectedRepeat.copied == 0 && selectedRepeat.existing == 1)
        precondition(!fm.fileExists(atPath: destination.appendingPathComponent("Selected/new.txt").path))
        let none = try BackupEngine().run(source: source, destination: destination, folder: "None", checkOnly: false, selectedPaths: [], progress: { _ in })
        precondition(none.copied == 0 && !fm.fileExists(atPath: destination.appendingPathComponent("None").path))
        print("PASS: checked files copied, unchecked files excluded, repeated selection skips existing, files added after review excluded, empty selection copies nothing")
        print("PASS: check-only, first copy, duplicate skip, changed-file preservation, repeat conflict skip, source symlink exclusion, overlap rejection, traversal rejection, destination symlink rejection, cancellation, source preservation")
    }
}
