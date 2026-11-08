import SwiftUI
import AppKit

struct DuplicateResultsView: View {
    @ObservedObject var session: FileReviewSession
    let forBackup: Bool
    let onBack: () -> Void
    let onBackup: ((Set<String>) -> Void)?
    private var report: DuplicateReport { session.report }
    private var visibleCount: Int { session.tab == 0 ? session.rows.count : session.files.count }
    private var canCheck: Bool { forBackup && session.tab != 2 }

    var body: some View {
        VStack(spacing: 0) {
            pageHeader
            Divider()
            HStack(alignment: .top, spacing: 0) {
                filterSidebar
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    listToolbar
                    if !report.complete {
                        Label("Scan incomplete. Unmatched files may still have duplicates in unscanned folders.", systemImage: "exclamationmark.triangle")
                            .font(.system(size: 12)).foregroundStyle(BackupTheme.muted)
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    }
                    bulkActions
                    fileTable
                        .overlay {
                            if visibleCount == 0 {
                                VStack(spacing: 10) {
                                    Image(systemName: "line.3.horizontal.decrease.circle").font(.system(size: 28)).foregroundStyle(BackupTheme.muted)
                                    Text("No files match these filters").font(.headline)
                                    Button("Clear filters") { session.filter = FileReviewFilter() }
                                }.padding(20).background(BackupTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    selectionDetails
                    if !report.errors.isEmpty {
                        DisclosureGroup("\(report.errors.count) scan issues", isExpanded: $session.showIssues) {
                            ScrollView {
                                Text(report.errors.joined(separator: "\n\n")).font(.system(size: 12)).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }.frame(height: 80).padding(.top, 8)
                        }.font(.system(size: 12))
                    }
                }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            pageFooter
        }
        .frame(minWidth: 1040, idealWidth: 1200, minHeight: 720, idealHeight: 840)
        .background(BackupTheme.canvas)
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                Button(action: onBack) { Label("Setup", systemImage: "chevron.left") }
                    .controlSize(.large).keyboardShortcut(.cancelAction)
                    .help("Return to backup setup. Review choices are kept until you scan again.")
                Rectangle().fill(BackupTheme.border).frame(width: 1, height: 24)
                AppLogo(size: 40).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(forBackup ? "Review your backup" : "Duplicate results").font(.system(size: 24, weight: .semibold, design: .rounded))
                    Text(forBackup ? "Filter the list, select rows, then check the files you want to include." : "Browse and filter the files found on both drives.")
                        .font(.system(size: 13)).foregroundStyle(BackupTheme.muted)
                }
                Spacer()
                Text(forBackup ? "02 / REVIEW FILES" : "FILE COMPARISON")
                    .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(BackupTheme.muted)
            }
            HStack(spacing: 20) {
                route("From", path: report.source.path, icon: "sdcard")
                Image(systemName: "arrow.right").foregroundStyle(BackupTheme.muted).accessibilityHidden(true)
                route("To", path: report.destination.path, icon: "externaldrive")
            }
        }.padding(.horizontal, 24).padding(.vertical, 20).background(BackupTheme.surface)
    }

    private func route(_ title: String, path: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(BackupTheme.accent).accessibilityHidden(true)
            Text(title).fontWeight(.semibold)
            Text(path).foregroundStyle(BackupTheme.muted).lineLimit(1).truncationMode(.middle).help(path).textSelection(.enabled)
        }.font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
    }

    private var filterSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Label("Filters", systemImage: "line.3.horizontal.decrease").font(.headline)
                    Spacer()
                    Button("Reset") { session.filter = FileReviewFilter() }.buttonStyle(.link)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("File extension").font(.system(size: 13, weight: .semibold))
                    Picker("File extension", selection: $session.filter.fileExtension) {
                        Text("All extensions").tag(String?.none)
                        ForEach(session.extensions, id: \.self) { ext in
                            Text(ext.isEmpty ? "No extension" : ".\(ext)").tag(Optional(ext))
                        }
                    }.labelsHidden()
                    Text("Options come from this file list.").font(.system(size: 12)).foregroundStyle(BackupTheme.muted)
                }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Text("File size").font(.system(size: 13, weight: .semibold))
                    comparisonPicker("Size comparison", selection: $session.filter.sizeComparison)
                    HStack(spacing: 8) {
                        TextField("e.g. 1.5", text: $session.filter.sizeText)
                            .textFieldStyle(.roundedBorder).accessibilityLabel("File size threshold")
                        Picker("Size unit", selection: $session.filter.sizeUnit) {
                            ForEach(FileSizeUnit.allCases) { unit in Text(unit.rawValue).tag(unit) }
                        }.labelsHidden().frame(width: 76)
                    }.disabled(session.filter.sizeComparison == .any)
                    if let error = session.filter.sizeError {
                        Label(error, systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(.red)
                    } else {
                        Text("Compare exact sizes. 1 MB = 1,000,000 bytes.").font(.system(size: 12)).foregroundStyle(BackupTheme.muted)
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Text("Date created").font(.system(size: 13, weight: .semibold))
                    comparisonPicker("Creation date comparison", selection: $session.filter.createdComparison)
                    DatePicker("Created date", selection: $session.filter.createdDate, displayedComponents: .date)
                        .labelsHidden().datePickerStyle(.field)
                        .disabled(session.filter.createdComparison == .any)
                    Text("< before · > after · = on this day\nUses local calendar dates. Files with no creation date are excluded when this filter is active.")
                        .font(.system(size: 12)).foregroundStyle(BackupTheme.muted).fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                Text("100% duplicate = matching filename, extension, and exact size. Contents are verified during backup.")
                    .font(.system(size: 12)).foregroundStyle(BackupTheme.muted)
                Text("Filters change what you see. Checked files stay included even when hidden.")
                    .font(.system(size: 12)).foregroundStyle(BackupTheme.muted)
            }.padding(20)
        }.frame(width: 236).background(BackupTheme.surface.opacity(0.5))
    }

    private func comparisonPicker(_ label: String, selection: Binding<FileComparison>) -> some View {
        Picker(label, selection: selection) {
            ForEach(FileComparison.allCases) { comparison in Text(comparison.rawValue).tag(comparison) }
        }.pickerStyle(.segmented).labelsHidden().accessibilityLabel(label)
    }

    private var listToolbar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Picker("File list", selection: $session.tab) {
                    Text("Comparison (\(report.rows.count))").tag(0)
                    Text("From (\(report.sourceFiles.count))").tag(1)
                    Text("To (\(report.destinationFiles.count))").tag(2)
                }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 480)
                Spacer(minLength: 0)
                Text("\(visibleCount) shown").font(.system(size: 12)).foregroundStyle(BackupTheme.muted)
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(BackupTheme.muted).accessibilityHidden(true)
                TextField("Search file names or paths", text: $session.filter.search).textFieldStyle(.plain)
                    .accessibilityLabel("Search file names or paths")
                if !session.filter.search.isEmpty {
                    Button { session.filter.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).accessibilityLabel("Clear search")
                }
            }.padding(10).background(BackupTheme.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(BackupTheme.border))
        }
    }

    private var bulkActions: some View {
        HStack(spacing: 10) {
            Text("\(session.highlighted.count) rows selected").font(.system(size: 12, weight: .medium))
            if canCheck {
                Button("Check Selected") { session.setIncluded(session.actionableHighlight, true) }
                    .disabled(session.actionableHighlight.isEmpty)
                Button("Uncheck Selected") { session.setIncluded(session.actionableHighlight, false) }
                    .disabled(session.actionableHighlight.isEmpty)
                Menu {
                    Button("Check All Visible") { session.setIncluded(session.visibleIDs, true) }
                    Button("Uncheck All Visible") { session.setIncluded(session.visibleIDs, false) }
                    Divider()
                    Button("Check All Source Files") { session.setIncluded(Set(report.sourceFiles.map(\.id)), true) }
                    Button("Uncheck All Source Files") { session.setIncluded(Set(report.sourceFiles.map(\.id)), false) }
                } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).frame(width: 24)
                    .accessibilityLabel("More file inclusion actions")
            }
            Spacer(minLength: 0)
        }.controlSize(.small)
    }

    private var fileTable: some View {
        GeometryReader { geometry in
            tableContent(width: geometry.size.width)
        }
    }

    // Branch outside TableColumnBuilder: optional columns require macOS 14.4.
    @ViewBuilder private func tableContent(width: CGFloat) -> some View {
        if session.tab == 0 {
            if forBackup {
                Table(session.rows, selection: $session.highlighted) {
                    TableColumn("Include") { row in includeToggle(row.file) }.width(52)
                    TableColumn("Source File") { row in path(row.file.url.path) }.width(max(120, (width - (forBackup ? 425 : 355)) / 2))
                    TableColumn("Size") { row in size(row.file) }.width(80)
                    TableColumn("Created") { row in created(row.file) }.width(90)
                    TableColumn("Duplicate %") { row in
                        Text(row.matches.isEmpty ? (report.complete ? "0%" : "—") : "100%").monospacedDigit()
                    }.width(85)
                    TableColumn("Duplicate File Loc") { row in
                        path(row.matches.isEmpty ? (report.complete ? "No duplicate" : "Scan incomplete") : row.matches.map { $0.url.path }.joined(separator: "\n"))
                    }.width(max(120, (width - (forBackup ? 425 : 355)) / 2))
                }
            } else {
                Table(session.rows, selection: $session.highlighted) {
                    TableColumn("Source File") { row in path(row.file.url.path) }.width(max(120, (width - (forBackup ? 425 : 355)) / 2))
                    TableColumn("Size") { row in size(row.file) }.width(80)
                    TableColumn("Created") { row in created(row.file) }.width(90)
                    TableColumn("Duplicate %") { row in
                        Text(row.matches.isEmpty ? (report.complete ? "0%" : "—") : "100%").monospacedDigit()
                    }.width(85)
                    TableColumn("Duplicate File Loc") { row in
                        path(row.matches.isEmpty ? (report.complete ? "No duplicate" : "Scan incomplete") : row.matches.map { $0.url.path }.joined(separator: "\n"))
                    }.width(max(120, (width - (forBackup ? 425 : 355)) / 2))
                }
            }
        } else if canCheck {
            Table(session.files, selection: $session.highlighted) {
                TableColumn("Include") { file in includeToggle(file) }.width(52)
                TableColumn("File") { file in path(file.url.path) }.width(max(180, width - (canCheck ? 425 : 355)))
                TableColumn("Extension") { file in Text(file.format) }.width(85)
                TableColumn("Size") { file in size(file) }.width(90)
                TableColumn("Created") { file in created(file) }.width(100)
            }
        } else {
            Table(session.files, selection: $session.highlighted) {
                TableColumn("File") { file in path(file.url.path) }.width(max(180, width - (canCheck ? 425 : 355)))
                TableColumn("Extension") { file in Text(file.format) }.width(85)
                TableColumn("Size") { file in size(file) }.width(90)
                TableColumn("Created") { file in created(file) }.width(100)
            }
        }
    }

    private var selectionDetails: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Use ⌘-click for multiple rows or Shift-click for a range. Checkboxes control backup inclusion.")
                .font(.system(size: 12)).foregroundStyle(BackupTheme.muted)
            if session.highlighted.count == 1, let id = session.highlighted.first {
                DisclosureGroup("Selected file details") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(id).textSelection(.enabled)
                            if let row = report.rows.first(where: { $0.id == id }) {
                                ForEach(row.matches) { file in
                                    HStack {
                                        Text(file.url.path).textSelection(.enabled)
                                        Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }.buttonStyle(.link)
                                    }
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 90)
                }.font(.system(size: 12))
            }
        }
    }

    private var pageFooter: some View {
        HStack(spacing: 20) {
            if forBackup {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(session.included.count) files checked · \(ByteCountFormatter.string(fromByteCount: session.includedBytes, countStyle: .file))")
                        .font(.system(size: 14, weight: .semibold))
                    Text(session.tab == 2 ? "Destination files are shown for reference. Inclusion applies to source files." : "\(session.hiddenIncludedCount) checked files hidden by the current view or filters.")
                        .font(.system(size: 12)).foregroundStyle(BackupTheme.muted)
                }
                Spacer()
                Button("Back Up Checked Files (\(session.included.count))") { onBackup?(session.included) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(session.included.isEmpty || onBackup == nil)
            } else {
                Text("\(report.rows.filter { !$0.matches.isEmpty }.count) source files with matches · Read-only comparison")
                    .font(.system(size: 13)).foregroundStyle(BackupTheme.muted)
                Spacer()
                Button("Back to Setup", action: onBack).controlSize(.large)
            }
        }.padding(.horizontal, 24).padding(.vertical, 20).background(BackupTheme.surface)
            .help("100% means filename, extension, and exact size match. Backup still verifies file contents before skipping copies.")
    }

    private func includeToggle(_ file: InventoryFile) -> some View {
        Toggle("Include \(file.url.lastPathComponent)", isOn: Binding(
            get: { session.included.contains(file.id) },
            set: { session.setIncluded([file.id], $0) }
        )).toggleStyle(.checkbox).labelsHidden().accessibilityLabel("Include \(file.url.path) in backup")
    }
    private func size(_ file: InventoryFile) -> some View {
        Text(file.sizeLabel).monospacedDigit().help("\(file.size) bytes")
    }
    private func created(_ file: InventoryFile) -> some View {
        Text(file.created.map { $0.formatted(date: .numeric, time: .omitted) } ?? "Unknown")
            .help(file.created.map { $0.formatted(date: .complete, time: .standard) } ?? "Creation date unavailable")
    }
    private func path(_ value: String) -> some View {
        Text(value).lineLimit(1).truncationMode(.middle).help(value)
            .contextMenu {
                if canCheck {
                    Button("Check Selected Rows") { session.setIncluded(session.actionableHighlight, true) }.disabled(session.actionableHighlight.isEmpty)
                    Button("Uncheck Selected Rows") { session.setIncluded(session.actionableHighlight, false) }.disabled(session.actionableHighlight.isEmpty)
                }
                Button("Copy Path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string) }
            }
    }
}
