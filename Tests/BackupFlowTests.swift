import Foundation

@main
struct BackupFlowTests {
    @MainActor static func main() async throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: base) }
        let from = base.appendingPathComponent("from")
        let to = base.appendingPathComponent("to")
        try fm.createDirectory(at: from, withIntermediateDirectories: true)
        try fm.createDirectory(at: to, withIntermediateDirectories: true)
        try Data("include".utf8).write(to: from.appendingPathComponent("yes.txt"))
        try Data("exclude".utf8).write(to: from.appendingPathComponent("no.txt"))
        let model = BackupModel()
        model.source = from
        model.destination = to
        model.folder = "Review"
        model.prepareBackup()
        for _ in 0..<500 {
            if !model.busy { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        precondition(!model.busy && model.showDuplicates && model.reviewingBackup)
        precondition(model.duplicates?.rows.count == 2)
        let beforeConfirmation = try fm.contentsOfDirectory(atPath: to.path)
        precondition(beforeConfirmation.isEmpty)
        let chosen = model.duplicates!.sourceFiles.first { $0.url.lastPathComponent == "yes.txt" }!
        let session = model.reviewSession!
        session.setIncluded(Set(session.report.sourceFiles.map(\.id)), false)
        session.highlighted = [chosen.id]
        session.setIncluded(session.actionableHighlight, true)
        session.filter.search = "yes.txt"
        model.showDuplicates = false
        model.showDuplicates = true
        precondition(model.reviewSession === session && session.included == [chosen.id] && session.filter.search == "yes.txt")
        model.backUpSelected(session.included)
        precondition(model.showProgress && model.busy && !model.showDuplicates)
        for _ in 0..<500 {
            if !model.busy { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        precondition(!model.busy && !model.showDuplicates)
        precondition(model.report?.copied == 1)
        precondition(model.showProgress && model.transfer.percentage == 100 && model.transfer.copied == 1)
        precondition(fm.fileExists(atPath: to.appendingPathComponent("Review/yes.txt").path))
        precondition(!fm.fileExists(atPath: to.appendingPathComponent("Review/no.txt").path))
        print("PASS: Start Backup opens review without writing; navigation preserves filters and inclusion; confirmation copies only checked files")
    }
}
