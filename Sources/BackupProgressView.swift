import SwiftUI
import AppKit

struct BackupProgressView: View {
    @ObservedObject var model: BackupModel
    @State private var showIssues = false
    private var progress: BackupProgress { model.transfer }
    private var terminal: Bool { !model.busy }
    private var hasIssues: Bool { progress.issues > 0 || progress.phase == .failed }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .center, spacing: 32) {
                        percentageGraph
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(spacing: 8) {
                                Image(systemName: (model.stopping && model.busy) || progress.phase == .stopped ? "pause.circle" : (hasIssues ? "exclamationmark.triangle" : (terminal ? "checkmark.circle" : "arrow.up.doc")))
                                    .foregroundStyle(hasIssues ? Color.orange : BackupTheme.accent)
                                Text(model.status).font(.system(size: 20, weight: .semibold))
                            }
                            Text(terminal ? model.detail : progress.phase.rawValue)
                                .font(.system(size: 14)).foregroundStyle(BackupTheme.muted)
                            ProgressView(value: progress.fraction).tint(BackupTheme.accent)
                                .accessibilityLabel("Overall backup progress")
                            HStack {
                                Text("\(progress.processedFiles) of \(progress.totalFiles) files processed")
                                Spacer()
                                Text("\(bytes(progress.totalBytes)) selected")
                            }.font(.system(size: 12)).foregroundStyle(BackupTheme.muted).monospacedDigit()
                            Text("Overall progress includes reading, copying, and verification.")
                                .font(.system(size: 12)).foregroundStyle(BackupTheme.muted)
                        }
                    }.padding(28).frame(maxWidth: .infinity)
                        .background(BackupTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(BackupTheme.border))
                    HStack(spacing: 16) {
                        metric("Transfer speed", value: speedLabel, icon: "speedometer")
                        metric("Estimated time left", value: remainingLabel, icon: "hourglass")
                        metric("Elapsed time", value: duration(progress.elapsedSeconds), icon: "clock")
                    }
                    currentFile
                    HStack(alignment: .center, spacing: 28) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Recent transfer speed").font(.system(size: 13, weight: .semibold))
                            speedGraph.frame(height: 65)
                            Text("\(bytes(progress.transferredBytes)) written · Speed drops to zero while checking or verifying.")
                                .font(.system(size: 12)).foregroundStyle(BackupTheme.muted)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Divider().frame(height: 95)
                        HStack(spacing: 28) {
                            count("Copied", value: progress.copied)
                            count("Already saved", value: progress.existing)
                            count("Issues", value: progress.issues)
                        }
                    }.padding(20).background(BackupTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                    if let report = model.report, !report.errors.isEmpty {
                        DisclosureGroup("Review \(report.errors.count) issues", isExpanded: $showIssues) {
                            Text(report.errors.joined(separator: "\n\n")).font(.system(size: 12)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                        }.font(.system(size: 13))
                    }
                }.padding(24).frame(maxWidth: 1120).frame(maxWidth: .infinity)
            }
            Divider()
            footer
        }.frame(minWidth: 900, idealWidth: 1040, minHeight: 740, idealHeight: 900)
            .background(BackupTheme.canvas)
    }

    private var header: some View {
        HStack(spacing: 16) {
            AppLogo(size: 52).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text("Your backup").font(.system(size: 25, weight: .semibold, design: .rounded))
                Text("A verified copy, from source to destination.").font(.system(size: 13)).foregroundStyle(BackupTheme.muted)
            }
            Spacer()
            HStack(spacing: 12) {
                Label("Setup", systemImage: "checkmark.circle.fill")
                Image(systemName: "chevron.right").font(.system(size: 10))
                Label("Review", systemImage: "checkmark.circle.fill")
                Image(systemName: "chevron.right").font(.system(size: 10))
                Text("03  Backup").fontWeight(.semibold).foregroundStyle(BackupTheme.accent)
            }.font(.system(size: 12)).foregroundStyle(BackupTheme.muted)
        }.padding(.horizontal, 24).padding(.vertical, 20).background(BackupTheme.surface)
    }

    private var percentageGraph: some View {
        ZStack {
            Circle().stroke(BackupTheme.accent.opacity(0.12), lineWidth: 14)
            Circle().trim(from: 0, to: progress.fraction)
                .stroke(BackupTheme.accent, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 5) {
                Text("\(progress.percentage)%").font(.system(size: 42, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(terminal ? progress.phase.rawValue : "Overall progress").font(.system(size: 12)).foregroundStyle(BackupTheme.muted)
            }
        }.frame(width: 180, height: 180).padding(8)
            .accessibilityElement(children: .ignore).accessibilityLabel("Overall progress").accessibilityValue("\(progress.percentage) percent")
    }

    private var currentFile: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(terminal ? (progress.phase == .finished ? "Last processed file" : "Last active file") : "Current file", systemImage: "doc")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(progress.phase.rawValue).font(.system(size: 12)).foregroundStyle(BackupTheme.muted)
            }
            Text(progress.currentFile ?? (terminal ? "No files processed" : "Preparing the file list…"))
                .font(.system(size: 14, weight: .medium)).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if !terminal && [.copying, .verifyingCopy, .verifyingSource].contains(progress.phase) {
                ProgressView(value: progress.currentFileBytes > 0 ? min(1, Double(progress.currentFileTransferred) / Double(progress.currentFileBytes)) : 1)
                    .accessibilityLabel("Current file copied")
                Text("\(bytes(progress.currentFileTransferred)) of \(bytes(progress.currentFileBytes)) copied")
                    .font(.system(size: 12)).foregroundStyle(BackupTheme.muted).monospacedDigit()
            }
            if let target = model.backupTarget {
                Label(target.path, systemImage: "externaldrive").font(.system(size: 12)).foregroundStyle(BackupTheme.muted)
                    .textSelection(.enabled).help(target.path)
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(BackupTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(BackupTheme.border))
    }

    private var speedGraph: some View {
        Canvas { context, size in
            let samples = model.speedSamples
            guard samples.count > 1, let first = samples.first, let last = samples.last else { return }
            let timeRange = max(0.01, last.elapsed - first.elapsed)
            let peak = max(1, samples.map(\.bytesPerSecond).max() ?? 1)
            var line = Path()
            for (index, sample) in samples.enumerated() {
                let point = CGPoint(x: (sample.elapsed - first.elapsed) / timeRange * size.width,
                                    y: size.height - min(1, sample.bytesPerSecond / peak) * (size.height - 4))
                if index == 0 { line.move(to: point) } else { line.addLine(to: point) }
            }
            var fill = line
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height)); fill.closeSubpath()
            context.fill(fill, with: .color(BackupTheme.accent.opacity(0.10)))
            context.stroke(line, with: .color(BackupTheme.accent), lineWidth: 2)
        }.accessibilityLabel("Recent transfer speed graph").accessibilityValue(speedLabel)
    }

    private func metric(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.system(size: 12)).foregroundStyle(BackupTheme.muted)
            Text(value).font(.system(size: 23, weight: .medium, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(BackupTheme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(BackupTheme.border))
    }
    private func count(_ title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value.formatted()).font(.system(size: 24, weight: .medium, design: .rounded)).monospacedDigit()
            Text(title).font(.system(size: 12)).foregroundStyle(BackupTheme.muted)
        }
    }
    private var footer: some View {
        HStack(spacing: 16) {
            Label("Originals stay untouched", systemImage: "checkmark.shield").font(.system(size: 12)).foregroundStyle(BackupTheme.muted)
            Spacer()
            Button("Show in Finder") {
                if let target = model.backupTarget {
                    NSWorkspace.shared.open(FileManager.default.fileExists(atPath: target.path) ? target : target.deletingLastPathComponent())
                }
            }.controlSize(.large).disabled(model.backupTarget == nil)
            if model.busy {
                Button(model.stopping ? "Stopping…" : "Stop Backup") { model.cancel() }
                    .controlSize(.large).disabled(model.stopping)
            } else {
                Button("Back to Setup") { model.showProgress = false }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
        }.padding(.horizontal, 24).padding(.vertical, 20).background(BackupTheme.surface)
    }
    private var speedLabel: String {
        progress.phase == .copying && progress.bytesPerSecond > 0 ? "\(bytes(Int64(min(Double(Int64.max - 1024), progress.bytesPerSecond))))/s" : "0 B/s"
    }
    private var remainingLabel: String {
        if progress.phase == .finished { return "Complete" }
        if [.stopped, .failed].contains(progress.phase) { return "—" }
        return progress.secondsRemaining.map { duration($0) } ?? "Calculating…"
    }
    private func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }
    private func duration(_ value: Double) -> String {
        guard value.isFinite && value >= 0 && value < Double(Int.max - 1024) else { return "Calculating…" }
        let seconds = Int(value.rounded(.up))
        if seconds >= 3600 { return "\(seconds / 3600)h \((seconds % 3600) / 60)m" }
        if seconds >= 60 { return "\(seconds / 60)m \(seconds % 60)s" }
        return "\(seconds)s"
    }
}
