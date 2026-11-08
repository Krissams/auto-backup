import Foundation

@main
struct FileReviewTests {
    @MainActor static func main() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Manila")!
        let reference = calendar.date(from: DateComponents(year: 2026, month: 5, day: 1, hour: 13))!
        let earlier = calendar.date(byAdding: .day, value: -1, to: reference)!
        let later = calendar.date(byAdding: .day, value: 1, to: reference)!
        let first = InventoryFile(url: URL(fileURLWithPath: "/source/one.INSV"), size: 1_500_000, created: reference)
        let second = InventoryFile(url: URL(fileURLWithPath: "/source/two.txt"), size: 500, created: earlier)
        let third = InventoryFile(url: URL(fileURLWithPath: "/source/three.insv"), size: 3_000_000, created: later)
        let unknown = InventoryFile(url: URL(fileURLWithPath: "/source/no-extension"), size: 0)
        var filter = FileReviewFilter()
        filter.fileExtension = "insv"
        precondition(filter.matches(first) && filter.matches(third) && !filter.matches(second))
        filter.sizeComparison = .equal
        filter.sizeText = "1.5"
        filter.sizeUnit = .mb
        precondition(filter.matches(first) && !filter.matches(third))
        filter.sizeComparison = .greater
        precondition(!filter.matches(first) && filter.matches(third))
        filter.sizeComparison = .less
        filter.fileExtension = nil
        precondition(filter.matches(second) && !filter.matches(first))
        for invalid in ["-1", "abc", "1garbage", "", "1.2.3"] {
            filter.sizeText = invalid
            precondition(filter.sizeError != nil && !filter.matches(first))
        }
        filter = FileReviewFilter()
        filter.createdDate = calendar.startOfDay(for: reference)
        filter.createdComparison = .equal
        precondition(filter.matches(first, calendar: calendar))
        precondition(!filter.matches(second, calendar: calendar) && !filter.matches(third, calendar: calendar) && !filter.matches(unknown, calendar: calendar))
        filter.createdComparison = .less
        precondition(filter.matches(second, calendar: calendar) && !filter.matches(first, calendar: calendar))
        filter.createdComparison = .greater
        precondition(filter.matches(third, calendar: calendar) && !filter.matches(first, calendar: calendar))
        filter = FileReviewFilter()
        filter.search = "destination/copy"
        precondition(filter.matches(first, additionalPaths: ["/destination/copy.insv"]))
        precondition(!filter.matches(first))
        let target = InventoryFile(url: URL(fileURLWithPath: "/destination/movie.mp4"), size: 700)
        var report = DuplicateReport(source: URL(fileURLWithPath: "/source"), destination: URL(fileURLWithPath: "/destination"))
        report.sourceFiles = [first, second, third, unknown]
        report.destinationFiles = [target]
        report.rows = report.sourceFiles.map { DuplicateRow(file: $0, matches: []) }
        let session = FileReviewSession(report: report)
        precondition(session.extensions == ["", "insv", "txt"])
        session.highlighted = [first.id, second.id]
        session.setIncluded(session.actionableHighlight, false)
        precondition(!session.included.contains(first.id) && !session.included.contains(second.id) && session.included.contains(third.id))
        session.setIncluded(session.actionableHighlight, true)
        precondition(session.included.count == 4)
        session.filter.fileExtension = "insv"
        precondition(session.visibleIDs == [first.id, third.id] && session.highlighted == [first.id])
        session.setIncluded(session.visibleIDs, false)
        precondition(session.included == [second.id, unknown.id] && session.hiddenIncludedCount == 2)
        session.filter = FileReviewFilter()
        precondition(session.included == [second.id, unknown.id] && session.visibleIDs.count == 4)
        session.tab = 2
        precondition(session.extensions == ["mp4"] && session.highlighted.isEmpty && session.actionableHighlight.isEmpty)
        session.setIncluded([target.id], true)
        precondition(!session.included.contains(target.id))
        session.tab = 0
        precondition(session.included == [second.id, unknown.id])
        print("PASS: extension discovery, size < > = with decimal units, invalid sizes, created-day < > = and unknown dates, path search, multi-row check/uncheck, filtered bulk actions, hidden inclusion retention, tab safety")
    }
}
