#!/bin/zsh
set -eu
cd "${0:A:h}/.."
# The preview bundle has its own identity and uses synthetic data only.
if [[ ! -f 'build/Auto Backup.app/Contents/Resources/AutoBackupMark.png' ]]; then
    zsh scripts/build.sh
fi
PREVIEW_APP="$PWD/build/DocumentationPreview.app"
mkdir -p "$PREVIEW_APP/Contents/MacOS" "$PREVIEW_APP/Contents/Resources" docs/screenshots
cp 'build/Auto Backup.app/Contents/Resources/AutoBackupMark.png' "$PREVIEW_APP/Contents/Resources/AutoBackupMark.png"
cat > "$PREVIEW_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Preview</string>
<key>CFBundleIdentifier</key><string>local.autobackup.documentation-preview</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
sed '/^@main/,$d' Sources/AutoBackupApp.swift > build/BackupAppForDocumentation.swift
xcrun swiftc -target "$(uname -m)-apple-macosx13.0" -swift-version 5 -parse-as-library \
    Sources/BackupProgress.swift Sources/BackupEngine.swift Sources/DuplicateScanner.swift \
    Sources/FileReviewSession.swift Sources/DuplicateResultsView.swift Sources/BackupProgressView.swift \
    build/BackupAppForDocumentation.swift scripts/render-previews.swift \
    -o "$PREVIEW_APP/Contents/MacOS/Preview" -framework SwiftUI -framework AppKit -framework CryptoKit
"$PREVIEW_APP/Contents/MacOS/Preview"
cp build/AutoBackup.iconset/icon_256x256@2x.png docs/app-icon.png
echo 'Rendered docs/screenshots with synthetic examples.'
