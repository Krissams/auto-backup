import Foundation

@main
struct DuplicateScannerTests {
    static func main() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: base) }
        let source = base.appendingPathComponent("from")
        let destination = base.appendingPathComponent("to")
        func write(_ root: URL, _ path: String, _ contents: String) throws {
            let file = root.appendingPathComponent(path)
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: file)
        }
        try write(source, "test.txt", "one")
        try write(source, "test2.txt", "two")
        try write(source, "different-size.txt", "large")
        try write(source, "different-format.txt", "a")
        try write(source, "zero.bin", "")
        try write(source, ".hidden", "hidden")
        try write(destination, "nested/test2.txt", "xyz")
        try write(destination, "another/test2.TXT", "two")
        try write(destination, "different-size.txt", "s")
        try write(destination, "different-format.csv", "a")
        try write(destination, "zero.bin", "")
        try write(destination, "other.txt", "one")
        try fm.createSymbolicLink(at: source.appendingPathComponent("link"), withDestinationURL: destination)
        let report = try DuplicateScanner().run(source: source, destination: destination, progress: { _ in })
        precondition(report.complete && report.errors.isEmpty)
        precondition(report.sourceFiles.count == 6 && report.destinationFiles.count == 6)
        precondition(report.rows.count == 6 && report.excluded == 1)
        func matches(_ name: String) -> Int { report.rows.first { $0.file.url.lastPathComponent == name }!.matches.count }
        precondition(matches("test.txt") == 0)
        precondition(matches("test2.txt") == 2)
        precondition(matches("different-size.txt") == 0)
        precondition(matches("different-format.txt") == 0)
        precondition(matches("zero.bin") == 1)
        precondition(matches(".hidden") == 0)
        let stopped = DuplicateScanner()
        stopped.cancel()
        let partial = try stopped.run(source: source, destination: destination, progress: { _ in })
        precondition(!partial.complete)
        do {
            _ = try DuplicateScanner().run(source: source, destination: source, progress: { _ in })
            fatalError("Same folder should be rejected")
        } catch is BackupFailure {}
        do {
            _ = try DuplicateScanner().run(source: source, destination: base.appendingPathComponent("missing"), progress: { _ in })
            fatalError("Missing folder should fail")
        } catch {}
        let before = try String(contentsOf: destination.appendingPathComponent("nested/test2.txt"), encoding: .utf8)
        precondition(before == "xyz")
        print("PASS: recursive inventories, metadata matching without content matching, all locations, extension normalization, different name/size/format, empty and hidden files, symlinks, cancellation, invalid folders, read-only scan")
    }
}
