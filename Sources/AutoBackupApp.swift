import SwiftUI
import AppKit

@MainActor
final class BackupModel: ObservableObject {
    @Published var source: URL? {
        didSet {
            if source != oldValue { folder = defaultFolderName(); approvedPaths = nil }
        }
    }
    @Published var destination: URL? { didSet { if destination != oldValue { approvedPaths = nil } } }
    @Published var folder = "" { didSet { if folder != oldValue { approvedPaths = nil } } }
    @Published var automatic = false
    @Published var busy = false
    @Published var status = "Ready when you are"
    @Published var detail = "Choose a source and destination to get started."
    @Published var transfer = BackupProgress()
    @Published var speedSamples: [TransferSpeedSample] = []
    @Published var showProgress = false
    @Published var stopping = false
    @Published var backupTarget: URL?
    @Published var report: BackupReport?
    @Published var duplicates: DuplicateReport?
    @Published var showDuplicates = false
    @Published var reviewSession: FileReviewSession?
    @Published var reviewingBackup = false
    private var approvedPaths: Set<String>?
    private var scanner: DuplicateScanner?
    @Published var lastRun: Date?
    @Published var volumes: [URL] = []
    private var engine: BackupEngine?
    private var timer: Timer?
    private var activity: NSObjectProtocol?

    init() {
        let defaults = UserDefaults.standard
        source = defaults.string(forKey: "source").map { URL(fileURLWithPath: $0) }
        destination = defaults.string(forKey: "destination").map { URL(fileURLWithPath: $0) }
        let savedFolder = defaults.string(forKey: "folder")
        if let savedFolder, !savedFolder.isEmpty, savedFolder != "My Backup" {
            folder = savedFolder
        } else {
            folder = defaultFolderName()
        }
        refreshVolumes()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.automatic, !self.busy, !self.showDuplicates else { return }
                if let paths = self.approvedPaths { self.run(checkOnly: false, selectedPaths: paths) }
            }
        }
    }

    private func defaultFolderName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM d, yyyy - h:mma"
        let sourceName = source?.lastPathComponent.isEmpty == false ? source!.lastPathComponent : "SOURCE"
        let safeName = sourceName.replacingOccurrences(of: ":", with: "-")
        return "\(safeName)-\(formatter.string(from: Date()))"
    }

    func refreshVolumes() {
        volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeIsInternalKey], options: [.skipHiddenVolumes])?.filter {
            (try? $0.resourceValues(forKeys: [.volumeIsInternalKey]).volumeIsInternal) == false
        } ?? []
    }

    func choose(source isSource: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = isSource ? "Use as source" : "Use as destination"
        if panel.runModal() == .OK, let url = panel.url {
            if isSource { source = url } else { destination = url }
        }
    }

    func cancel() { engine?.cancel(); scanner?.cancel(); stopping = true; status = "Stopping safely…" }

    func prepareBackup() {
        guard !busy, let source, let destination else { return }
        do { _ = try BackupEngine().validate(source: source, destination: destination, folder: folder) }
        catch { status = "Check your folders"; detail = error.localizedDescription; return }
        checkDuplicates(forBackup: true)
    }

    func backUpSelected(_ paths: Set<String>) {
        guard !busy, !paths.isEmpty, let duplicates,
              duplicates.source.path == source?.standardizedFileURL.resolvingSymlinksInPath().path,
              duplicates.destination.path == destination?.standardizedFileURL.resolvingSymlinksInPath().path else { return }
        approvedPaths = paths.intersection(Set(duplicates.sourceFiles.map(\.id)))
        guard let approvedPaths, !approvedPaths.isEmpty else { return }
        showDuplicates = false
        reviewingBackup = false
        run(checkOnly: false, selectedPaths: approvedPaths)
    }

    func checkDuplicates(forBackup: Bool = false) {
        guard !busy, let source, let destination else { return }
        stopping = false
        reviewingBackup = forBackup
        let scanner = DuplicateScanner()
        self.scanner = scanner
        busy = true
        duplicates = nil
        status = "Checking duplicates…"
        detail = "Listing files in both selected folders, including subfolders…"
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Checking duplicate files")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var lastUpdate = Date.distantPast
            let result = Result {
                try scanner.run(source: source, destination: destination) { message in
                    guard Date().timeIntervalSince(lastUpdate) > 0.15 else { return }
                    lastUpdate = Date()
                    DispatchQueue.main.async { self?.detail = message }
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                self.scanner = nil
                if let activity = self.activity { ProcessInfo.processInfo.endActivity(activity) }
                self.activity = nil
                self.lastRun = Date()
                switch result {
                case .success(let report):
                    self.duplicates = report
                    self.reviewSession = FileReviewSession(report: report)
                    self.showDuplicates = true
                    self.status = report.complete ? "Duplicate check complete" : "Duplicate check incomplete"
                    let matched = report.rows.filter { !$0.matches.isEmpty }.count
                    self.detail = "\(report.sourceFiles.count) source files · \(report.destinationFiles.count) destination files · \(matched) source files with matches."
                case .failure(let error):
                    self.status = "Duplicate check couldn’t finish"
                    self.detail = error.localizedDescription
                }
            }
        }
    }

    func run(checkOnly: Bool, selectedPaths: Set<String>? = nil) {
        guard !busy, let source, let destination else { return }
        let engine = BackupEngine()
        do { _ = try engine.validate(source: source, destination: destination, folder: folder) }
        catch { status = "Check your folders"; detail = error.localizedDescription; return }
        self.engine = engine
        transfer = BackupProgress()
        speedSamples = []
        stopping = false
        backupTarget = destination.appendingPathComponent(folder.trimmingCharacters(in: .whitespacesAndNewlines))
        showProgress = !checkOnly
        showDuplicates = false
        busy = true
        report = nil
        status = checkOnly ? "Checking your backup…" : "Backup in progress…"
        detail = "Reading files and comparing SHA-256 checksums…"
        let folder = folder
        UserDefaults.standard.set(source.path, forKey: "source")
        UserDefaults.standard.set(destination.path, forKey: "destination")
        UserDefaults.standard.set(folder, forKey: "folder")
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Verifying and backing up files")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var lastUpdate = Date.distantPast
            let result = Result {
                try engine.run(source: source, destination: destination, folder: folder, checkOnly: checkOnly, selectedPaths: selectedPaths, telemetry: { snapshot in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.transfer = snapshot
                        self.speedSamples.append(TransferSpeedSample(elapsed: snapshot.elapsedSeconds, bytesPerSecond: snapshot.bytesPerSecond))
                        if self.speedSamples.count > 120 { self.speedSamples.removeFirst(self.speedSamples.count - 120) }
                    }
                }) { message in
                    guard Date().timeIntervalSince(lastUpdate) > 0.15 else { return }
                    lastUpdate = Date()
                    DispatchQueue.main.async { self?.detail = message }
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                if let activity = self.activity { ProcessInfo.processInfo.endActivity(activity) }
                self.activity = nil
                self.lastRun = Date()
                switch result {
                case .success(let report):
                    self.report = report
                    self.status = engine.cancelled ? "Backup stopped" : (!report.errors.isEmpty ? "Finished with issues" : (checkOnly ? "Backup check complete" : "Backup complete"))
                    self.detail = engine.cancelled ? "Completed copies are safe. Run again to continue." : (checkOnly ? "\(report.pending) files need backup. \(report.existing) already backed up." : "\(report.copied) files copied and verified. \(report.existing) already backed up.")
                case .failure(let error): self.status = "Backup couldn’t finish"; self.detail = error.localizedDescription; self.transfer.phase = .failed; self.transfer.secondsRemaining = nil
                }
                self.engine = nil
            }
        }
    }
}

struct AppLogo: View {
    var size: CGFloat = 44
    private static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "AutoBackupMark", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()
    var body: some View {
        Group {
            if let image = Self.image {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            } else {
                Image(systemName: "externaldrive.badge.checkmark").resizable().scaledToFit()
            }
        }.frame(width: size, height: size).accessibilityLabel("Auto Backup logo")
    }
}

enum BackupTheme {
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.40, green: 0.85, blue: 0.73, alpha: 1)
            : NSColor(red: 0.08, green: 0.39, blue: 0.32, alpha: 1)
    })
    static let muted = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0.72, alpha: 1)
            : NSColor(white: 0.38, alpha: 1)
    })
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let border = Color.primary.opacity(0.12)
}

struct BackupView: View {
    @StateObject private var model = BackupModel()
    @State private var showIssues = false
    private var ready: Bool {
        model.source != nil && model.destination != nil && !model.folder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var folderError: String? {
        if model.folder.contains("/") { return "Use a folder name without slashes." }
        if [".", ".."].contains(model.folder.trimmingCharacters(in: .whitespacesAndNewlines)) { return "Choose a name for your backup folder." }
        return nil
    }
    private var hasIssues: Bool { model.report?.errors.isEmpty == false }

    var body: some View {
        Group {
            if model.showProgress {
                BackupProgressView(model: model)
            } else if model.showDuplicates, let session = model.reviewSession {
                DuplicateResultsView(session: session, forBackup: model.reviewingBackup,
                    onBack: { model.showDuplicates = false },
                    onBackup: { model.backUpSelected($0) })
            } else {
                setupPage
            }
        }.tint(BackupTheme.accent)
    }

    private var setupPage: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Your backup route").font(.headline)
                            Spacer()
                            Button { model.refreshVolumes() } label: { Label("Refresh drives", systemImage: "arrow.clockwise") }
                                .buttonStyle(.borderless).disabled(model.busy)
                        }
                        HStack(alignment: .center, spacing: 16) {
                            location(title: "From", subtitle: "Files to back up", url: model.source, isSource: true)
                            Image(systemName: "arrow.right").font(.system(size: 18, weight: .medium))
                                .foregroundStyle(BackupTheme.muted).accessibilityHidden(true)
                            location(title: "To", subtitle: "Your backup destination", url: model.destination, isSource: false)
                        }
                        folderField
                    }.disabled(model.busy)
                    automaticBackup
                    activityPanel
                }.padding(24).frame(maxWidth: 1040).frame(maxWidth: .infinity)
            }
            Divider()
            actionBar
        }
        .frame(minWidth: 780, idealWidth: 880, minHeight: 680, idealHeight: 800)
        .background(BackupTheme.canvas)
        .tint(BackupTheme.accent)
    }

    private var header: some View {
        HStack(spacing: 16) {
            AppLogo(size: 60).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Auto Backup").font(.system(size: 30, weight: .semibold, design: .rounded))
                Text("Keep your files safe. Skip what’s already saved.").font(.system(size: 14)).foregroundStyle(BackupTheme.muted)
            }
            Spacer()
            Label("On your Mac", systemImage: "lock.shield")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(BackupTheme.muted)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(BackupTheme.surface, in: Capsule())
        }
    }

    private func location(title: String, subtitle: String, url: URL?, isSource: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: isSource ? "sdcard" : "externaldrive")
                    .font(.system(size: 22)).foregroundStyle(BackupTheme.accent)
                    .frame(width: 44, height: 44)
                    .background(BackupTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 16, weight: .semibold))
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(BackupTheme.muted)
                }
                Spacer(minLength: 0)
            }
            Menu {
                Button("Choose Folder…") { model.choose(source: isSource) }
                if !model.volumes.isEmpty {
                    Divider()
                    ForEach(model.volumes, id: \.path) { volume in
                        Button(volume.lastPathComponent) {
                            if isSource { model.source = volume } else { model.destination = volume }
                        }
                    }
                }
            } label: {
                Text(url?.lastPathComponent ?? (isSource ? "Choose source…" : "Choose destination…"))
                    .font(.system(size: 14, weight: .medium)).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }
            .controlSize(.large)
            .accessibilityLabel(isSource ? "Source folder" : "Destination folder")
            .accessibilityValue(url?.path ?? "Not selected")
            .help("Choose a folder or a connected drive")
            Text(url?.path ?? "Select a connected drive or browse for a folder.")
                .font(.system(size: 12)).foregroundStyle(BackupTheme.muted)
                .lineLimit(2).truncationMode(.middle).frame(height: 34, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(url?.path ?? "No folder selected")
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(BackupTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(BackupTheme.border))
    }

    private var folderField: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Backup folder name", systemImage: "folder").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("Editable").font(.system(size: 12)).foregroundStyle(BackupTheme.muted)
            }
            TextField("SOURCE-May 1, 2026 - 1:00PM", text: $model.folder)
                .textFieldStyle(.roundedBorder).controlSize(.large).font(.system(size: 14))
                .accessibilityLabel("Backup folder name")
                .accessibilityHint("Defaults to the source name and date. You can change it.")
            if let folderError {
                Label(folderError, systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(.red)
            } else {
                Text("Named from your source and date. Your original folder structure stays intact.")
                    .font(.system(size: 12)).foregroundStyle(BackupTheme.muted)
            }
        }.padding(20).background(BackupTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(BackupTheme.border))
    }

    private var automaticBackup: some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 20)).foregroundStyle(BackupTheme.accent).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Keep it backed up").font(.system(size: 14, weight: .semibold))
                Text("Repeat your reviewed file selection every 5 minutes while this app is open.")
                    .font(.system(size: 12)).foregroundStyle(BackupTheme.muted)
            }
            Spacer()
            Toggle("Automatic backup", isOn: $model.automatic).labelsHidden().toggleStyle(.switch)
                .accessibilityLabel("Automatically back up every five minutes")
        }.padding(20).background(BackupTheme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
    }

    private var activityPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if model.busy { ProgressView().controlSize(.small) }
                Text(model.status).font(.headline)
            }
            Text(model.detail).font(.system(size: 13)).foregroundStyle(BackupTheme.muted)
                .textSelection(.enabled)
            HStack(spacing: 20) {
                if model.duplicates != nil {
                    Button("View duplicate results") { model.reviewingBackup = false; model.showDuplicates = true }.buttonStyle(.link)
                }
                if model.transfer.phase != .preparing {
                    Button("View last backup") { model.showProgress = true }.buttonStyle(.link)
                }
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(BackupTheme.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    private var actionBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Originals stay untouched", systemImage: "checkmark.shield")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(BackupTheme.muted)
                Button("Show backup in Finder") {
                    if let destination = model.destination {
                        let target = destination.appendingPathComponent(model.folder)
                        NSWorkspace.shared.open(FileManager.default.fileExists(atPath: target.path) ? target : destination)
                    }
                }.buttonStyle(.link).font(.system(size: 12)).disabled(model.destination == nil)
            }
            Spacer(minLength: 8)
            if model.busy {
                Button("Stop") { model.cancel() }.controlSize(.large)
            } else {
                Button { model.checkDuplicates() } label: {
                    Label("Check Duplicates", systemImage: "doc.on.doc").padding(.vertical, 5)
                }.controlSize(.large).disabled(model.source == nil || model.destination == nil)
                    .help("List and compare all files in From and To by filename, format, and size")
                Button { model.prepareBackup() } label: {
                    Label("Start Backup", systemImage: "arrow.up.doc").padding(.horizontal, 8).padding(.vertical, 5)
                }.buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.return)
                    .disabled(!ready || folderError != nil)
            }
        }.padding(.horizontal, 32).padding(.vertical, 20).background(BackupTheme.surface)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let url = Bundle.main.url(forResource: "AutoBackup", withExtension: "icns"), let image = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = image
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct AutoBackupApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        WindowGroup { BackupView() }.defaultSize(width: 880, height: 820).windowResizability(.contentMinSize)
    }
}
