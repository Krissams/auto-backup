import Foundation
import Combine

enum FileComparison: String, CaseIterable, Identifiable {
    case any = "Any", less = "<", equal = "=", greater = ">"
    var id: String { rawValue }
    func accepts<T: Comparable>(_ value: T, comparedTo target: T) -> Bool {
        switch self {
        case .any: return true
        case .less: return value < target
        case .equal: return value == target
        case .greater: return value > target
        }
    }
}

enum FileSizeUnit: String, CaseIterable, Identifiable {
    case bytes = "bytes", kb = "KB", mb = "MB", gb = "GB"
    var id: String { rawValue }
    var multiplier: Decimal {
        switch self { case .bytes: return 1; case .kb: return 1_000; case .mb: return 1_000_000; case .gb: return 1_000_000_000 }
    }
}

struct FileReviewFilter: Equatable {
    var search = ""
    var fileExtension: String? = nil
    var sizeComparison: FileComparison = .any
    var sizeText = ""
    var sizeUnit: FileSizeUnit = .mb
    var createdComparison: FileComparison = .any
    var createdDate = Date()

    var sizeThreshold: Decimal? {
        let text = sizeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.range(of: #"^(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)$"#, options: .regularExpression) != nil,
              let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), value >= 0 else { return nil }
        return value * sizeUnit.multiplier
    }
    var sizeError: String? {
        sizeComparison != .any && sizeThreshold == nil ? "Enter a size of 0 or more, e.g. 1.5." : nil
    }
    var activeCount: Int {
        (fileExtension != nil ? 1 : 0) + (sizeComparison != .any ? 1 : 0) + (createdComparison != .any ? 1 : 0)
    }
    func matches(_ file: InventoryFile, additionalPaths: [String] = [], calendar: Calendar = .current) -> Bool {
        if !search.isEmpty && !([file.url.path] + additionalPaths).contains(where: { $0.localizedCaseInsensitiveContains(search) }) { return false }
        if let fileExtension, file.url.pathExtension.lowercased() != fileExtension { return false }
        if sizeComparison != .any {
            guard let threshold = sizeThreshold, sizeComparison.accepts(Decimal(file.size), comparedTo: threshold) else { return false }
        }
        if createdComparison != .any {
            guard let created = file.created else { return false }
            // Compare calendar days in local time; '=' includes the entire chosen day.
            guard createdComparison.accepts(calendar.startOfDay(for: created), comparedTo: calendar.startOfDay(for: createdDate)) else { return false }
        }
        return true
    }
}

@MainActor
final class FileReviewSession: ObservableObject {
    let report: DuplicateReport
    @Published var included: Set<String>
    @Published var highlighted: Set<String> = []
    @Published var filter = FileReviewFilter() { didSet { pruneHighlight() } }
    @Published var tab = 0 { didSet { changeTab() } }
    @Published var showIssues = false

    init(report: DuplicateReport) {
        self.report = report
        included = Set(report.sourceFiles.map(\.id))
    }
    var inventory: [InventoryFile] { tab == 2 ? report.destinationFiles : report.sourceFiles }
    var extensions: [String] { Set(inventory.map { $0.url.pathExtension.lowercased() }).sorted() }
    var rows: [DuplicateRow] {
        report.rows.filter { filter.matches($0.file, additionalPaths: $0.matches.map { $0.url.path }) }
    }
    var files: [InventoryFile] { inventory.filter { filter.matches($0) } }
    var visibleIDs: Set<String> { Set(tab == 0 ? rows.map(\.id) : files.map(\.id)) }
    var actionableHighlight: Set<String> { tab == 2 ? [] : highlighted.intersection(visibleIDs) }
    var hiddenIncludedCount: Int { included.subtracting(visibleIDs).count }
    var includedBytes: Int64 { report.sourceFiles.filter { included.contains($0.id) }.reduce(0) { $0 + $1.size } }
    func setIncluded(_ ids: Set<String>, _ checked: Bool) {
        let valid = ids.intersection(Set(report.sourceFiles.map(\.id)))
        if checked { included.formUnion(valid) } else { included.subtract(valid) }
    }
    func pruneHighlight() { highlighted.formIntersection(visibleIDs) }
    func changeTab() {
        highlighted.removeAll()
        if let ext = filter.fileExtension, !extensions.contains(ext) { filter.fileExtension = nil }
    }
}
