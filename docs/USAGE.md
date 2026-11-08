# User guide

Run build and test commands from the repository root. For installation, see the [README](../README.md).

A native macOS app for backing up SD cards, external drives, and folders. Requires macOS 13 or newer. No accounts, network services, or dependencies.

## Run

Open `build/Auto Backup.app`, or build it using `zsh scripts/build.sh` (requires Xcode command-line tools).

1. Choose **From**: a mounted removable drive or any source folder.
2. Choose **To**: a destination drive or folder.
3. The folder name defaults to `<SOURCE>-<DATE-TIME>` (for example, `EOS_DIGITAL-May 1, 2026 - 1:00PM`) using local time when the source is selected. You can edit it. The name stays fixed for repeat runs, and the last used name is restored when reopening the app so existing backups can still be skipped.
4. Select **Check Duplicates** to list and compare all files in the selected From and To folders (including subfolders), or **Start Backup** to review duplicates and choose which files to copy. All source files start checked. Uncheck unwanted files, then click **Back Up Checked Files**; no copies are made until you confirm. The duplicate scan searches the entire To folder independently of the backup folder name.
5. Optionally enable automatic backups every five minutes while the app is open. Automatic runs reuse the file selection from your last confirmed review and wait until you have confirmed a selection. Unchecked files and files added after the review are excluded. Click Start Backup again to review new files. Changing the source, destination, or backup folder clears the approved selection. Automatic mode and selections reset when the app restarts.

## File safety and matching

- Files keep their relative paths. SHA-256 content checks identify already backed-up files at those paths; matching names alone are insufficient. Identical files elsewhere are not globally deduplicated.
- Different content at an existing path is saved alongside the previous copy with a content-hash suffix. Repeat runs recognize these copies too.
- Copies are staged, verified against the source, and then moved into place without overwriting. Source files are never modified or deleted.
- Symbolic links are skipped; destination symlinks and overlapping source/backup folders are rejected. Empty directories are not copied.
- Errors are shown in the app. A disconnected drive requires reconnection. Scheduled runs retry on the next interval.
- Stop cancels between copy chunks and hash chunks, including during large file transfers. The hidden staged copy is removed when stopping. Abrupt app termination can leave a hidden `.autobackup-*.partial` file, which is never treated as a completed backup.
- The Mac stays awake during an active run. Automatic backups do not run while the app is closed or the Mac is sleeping. Keep both drives connected until the run finishes.
- Content verification reads files on every run, so a check can take time on large cards. This is a file backup, not a bootable disk clone.

## Verify

Run `zsh scripts/test.sh` to exercise copying, duplicate detection, conflict preservation, read-only checks, path protections, and cancellation using temporary test folders.

## Duplicate results

The full review page includes **Comparison**, **From**, and **To** tabs. Use **Setup** to return; your review filters and checked files are kept until the next scan. The comparison table shows **Source File**, **Size**, **Created**, **Duplicate %**, and **Duplicate File Loc**. Select a result and expand **Selected file details** to see every matching location and reveal it in Finder; right-click a path to copy it. Filter the lists with the search field.

- **100%** means filename stem, format (extension), and exact byte size all match. Filename stems are case-sensitive; extensions are case-insensitive. This is a metadata match, not proof of identical contents.
- **0% / No duplicate** means no matching file was found after a complete scan. There are no partial similarity scores.
- Cancelled or failed scans show **— / Scan incomplete** for unmatched files. Scan errors are available under **scan issues**.
- Both inventories include hidden regular files. Symbolic links are excluded. A file is never matched to its own path if the selected folders overlap.
- Duplicate scanning is read-only. Backup copying still uses SHA-256 verification, independently of this metadata report.

## Review filters and bulk inclusion

- **File extension:** choose from extensions present in the active From/To file inventory, including files without an extension. Extensions are case-insensitive.
- **File size:** choose `<`, `=`, or `>` and enter a nonnegative decimal value with bytes, KB, MB, or GB. Comparisons use exact bytes (decimal units: 1 MB = 1,000,000 bytes).
- **Date created:** choose `<` (before), `>` (after), or `=` (on the chosen day), using local calendar dates. This is the filesystem creation date. Files with unavailable creation dates are excluded while this filter is active.
- Search, extension, size, and date conditions combine. **Reset** clears the filters and search without changing the checked files.
- Use Command-click or Shift-click to select multiple rows. **Check Selected** / **Uncheck Selected** changes their backup inclusion. Individual checkboxes remain available.
- The more-actions menu includes **Check All Visible**, **Uncheck All Visible**, and actions for all source files. Filters never automatically remove hidden checked files. The footer shows the total count, bytes, and hidden checked count before backup.
- The To tab is for reference; only source files can be included. Highlighting a row and checking it for backup are separate actions.

## Backup progress (page 3)

After confirming the reviewed file selection, the app moves to a dedicated progress page and keeps it open for the final result. It shows:

- Overall percentage as a ring and progress bar, covering source reads, duplicate checks, copying, and verification. Skipped copies and failed files count as processed; any issues are shown separately. 100% appears only after the run finishes.
- Transfer speed measured from actual file-write chunks, plus a recent-speed graph. Speed is zero during content checks and verification.
- Estimated time remaining based on progress through the full run, including verification. It shows Calculating until there is enough progress to estimate. Estimates adjust as files are copied or found already saved.
- Elapsed time, the current file's full path and transfer bytes, the destination, live copied/skipped/issue counts, and a Stop Backup button.

Copying uses chunks and preserves file metadata. Completed copies are still SHA-256 verified and renamed into place only after verification. The supplied app icon is bundled for Finder and explicitly loaded for the Dock at launch. Restart the rebuilt app to load the updated icon and progress page.

## Finder icon

The build validates the bundled icon and refreshes the app's local Finder registration so a previously cached generic icon is replaced. CI checks the icon without registering the build on the runner. If Finder still displays a cached icon, leave and reopen the build folder, or run `xcrun swift scripts/register-app.swift "build/Auto Backup.app"` from the repository root. This refresh affects this app only.
