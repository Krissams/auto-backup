import Foundation

struct InventoryFile: Identifiable {
    let url: URL
    let size: Int64
    var created: Date? = nil
    var id: String { url.path }
    var sizeLabel: String { ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }
    var format: String { url.pathExtension.isEmpty ? "No extension" : url.pathExtension }
}

struct DuplicateRow: Identifiable {
    let file: InventoryFile
    let matches: [InventoryFile]
    var id: String { file.id }
}

struct DuplicateReport {
    let source: URL
    let destination: URL
    var sourceFiles: [InventoryFile] = []
    var destinationFiles: [InventoryFile] = []
    var rows: [DuplicateRow] = []
    var errors: [String] = []
    var excluded = 0
    var complete = false
}

final class DuplicateScanner: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    func cancel() { lock.lock(); stopped = true; lock.unlock() }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    private struct MatchKey: Hashable {
        let name: String
        let format: String
        let size: Int64
    var created: Date? = nil
        init(_ file: InventoryFile) {
            name = file.url.deletingPathExtension().lastPathComponent.precomposedStringWithCanonicalMapping
            format = file.url.pathExtension.lowercased()
            size = file.size
        }
    }

    func run(source: URL, destination: URL, progress: (String) -> Void) throws -> DuplicateReport {
        let source = source.standardizedFileURL.resolvingSymlinksInPath()
        let destination = destination.standardizedFileURL.resolvingSymlinksInPath()
        let fm = FileManager.default
        for root in [source, destination] {
            let values = try root.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { throw BackupFailure.invalid("Select a folder: \(root.path)") }
        }
        guard source.path != destination.path else { throw BackupFailure.invalid("Choose two different folders to compare.") }
        var report = DuplicateReport(source: source, destination: destination)
        func inventory(_ root: URL, label: String) throws -> [InventoryFile] {
            var files: [InventoryFile] = []
            let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .creationDateKey]
            guard let iterator = fm.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { url, error in
                report.errors.append("\(url.path): \(error.localizedDescription)")
                return true
            }) else { throw BackupFailure.invalid("Cannot read \(root.path)") }
            for case let url as URL in iterator {
                if cancelled { break }
                do {
                    let values = try url.resourceValues(forKeys: keys)
                    if values.isSymbolicLink == true { report.excluded += 1; continue }
                    guard values.isRegularFile == true else { continue }
                    guard let size = values.fileSize else { throw BackupFailure.invalid("Cannot read file size") }
                    files.append(InventoryFile(url: url.standardizedFileURL.resolvingSymlinksInPath(), size: Int64(size), created: values.creationDate))
                    progress("Listing \(label) · \(files.count.formatted()) files · \(url.lastPathComponent)")
                } catch { report.errors.append("\(url.path): \(error.localizedDescription)") }
            }
            return files.sorted { $0.url.path < $1.url.path }
        }
        report.sourceFiles = try inventory(source, label: "From")
        report.destinationFiles = try inventory(destination, label: "To")
        var index: [MatchKey: [InventoryFile]] = [:]
        for file in report.destinationFiles { index[MatchKey(file), default: []].append(file) }
        for file in report.sourceFiles {
            let matches = (index[MatchKey(file)] ?? []).filter { $0.url.path != file.url.path }
            report.rows.append(DuplicateRow(file: file, matches: matches))
        }
        report.complete = !cancelled && report.errors.isEmpty
        return report
    }
}
