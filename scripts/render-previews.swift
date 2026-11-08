// Documentation examples only: does not scan or copy files on user drives.
import SwiftUI
import AppKit

@main
struct DocumentationPreviews {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.appearance = NSAppearance(named: .darkAqua)
        UserDefaults.standard.setVolatileDomain([
            "source": "/Volumes/CAMERA CARD",
            "destination": "/Volumes/BACKUP SSD",
            "folder": "CAMERA CARD-May 1, 2026 - 1:00PM"
        ], forName: "NSArgumentDomain")
        try render(BackupView(), name: "setup", width: 960, height: 880)

        let source = URL(fileURLWithPath: "/Volumes/CAMERA CARD")
        let destination = URL(fileURLWithPath: "/Volumes/BACKUP SSD")
        var report = DuplicateReport(source: source, destination: destination)
        let names = ["VID_20260501_130000_001.insv", "VID_20260501_131500_002.insv", "VID_20260502_090000_003.insv",
                     "IMG_20260502_093000_004.jpg", "IMG_20260502_100000_005.jpg", "session-notes.txt", "preview.mp4",
                     "VID_20260503_080000_006.insv", "IMG_20260503_083000_007.jpg", "audio.wav", "summary.pdf"]
        for (index, name) in names.enumerated() {
            let file = InventoryFile(url: source.appendingPathComponent("DCIM/Camera01/\(name)"),
                                     size: Int64(index + 1) * 350_000_000,
                                     created: Date(timeIntervalSince1970: 1777597200 + Double(index * 3600)))
            report.sourceFiles.append(file)
            let matches = index % 3 == 0 ? [InventoryFile(url: destination.appendingPathComponent("Footage/May 2026/\(name)"), size: file.size, created: file.created)] : []
            report.destinationFiles.append(contentsOf: matches)
            report.rows.append(DuplicateRow(file: file, matches: matches))
        }
        report.complete = true
        let session = FileReviewSession(report: report)
        session.highlighted = Set(report.sourceFiles.prefix(3).map(\.id))
        session.setIncluded([report.sourceFiles[1].id], false)
        try render(DuplicateResultsView(session: session, forBackup: true, onBack: {}, onBackup: { _ in }),
                   name: "review", width: 1200, height: 900)

        let model = BackupModel()
        model.busy = true
        model.status = "Backup in progress…"
        model.transfer = BackupProgress(phase: .copying, fraction: 0.64, totalFiles: 29, processedFiles: 18,
            totalBytes: 142_500_000_000, transferredBytes: 87_200_000_000,
            currentFile: "/Volumes/CAMERA CARD/DCIM/Camera01/VID_20260501_130000_001.insv",
            currentFileBytes: 23_700_000_000, currentFileTransferred: 14_800_000_000,
            bytesPerSecond: 186_500_000, secondsRemaining: 325, elapsedSeconds: 581,
            copied: 13, existing: 5, issues: 0)
        model.backupTarget = destination.appendingPathComponent("CAMERA CARD-May 1, 2026 - 1:00PM")
        model.speedSamples = (0..<90).map { index in
            TransferSpeedSample(elapsed: Double(index) * 0.5,
                bytesPerSecond: 170_000_000 + sin(Double(index) * 0.3) * 35_000_000 + cos(Double(index) * 0.8) * 12_000_000)
        }
        try render(BackupProgressView(model: model), name: "progress", width: 1040, height: 960)
    }

    @MainActor static func render<Content: View>(_ content: Content, name: String, width: CGFloat, height: CGFloat) throws {
        let view = NSHostingView(rootView: content.environment(\.colorScheme, .dark).tint(BackupTheme.accent))
        let bounds = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.frame = bounds
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw BackupFailure.invalid("Unable to render \(name)")
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw BackupFailure.invalid("Unable to encode \(name)")
        }
        try png.write(to: URL(fileURLWithPath: "docs/screenshots/\(name).png"))
        window.orderOut(nil)
    }
}
