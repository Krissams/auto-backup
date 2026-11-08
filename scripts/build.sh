#!/bin/zsh
set -eu
cd "${0:A:h}/.."
APP="$PWD/build/Auto Backup.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun swift scripts/prepare-branding.swift "$APP/Contents/Resources" "$PWD/build/AutoBackup.iconset"
xcrun iconutil -c icns "$PWD/build/AutoBackup.iconset" -o "$APP/Contents/Resources/AutoBackup.icns"
xcrun swiftc -target "$(uname -m)-apple-macosx13.0" -swift-version 5 -O -parse-as-library Sources/BackupProgress.swift Sources/BackupEngine.swift Sources/DuplicateScanner.swift Sources/FileReviewSession.swift Sources/DuplicateResultsView.swift Sources/BackupProgressView.swift Sources/AutoBackupApp.swift -o "$APP/Contents/MacOS/AutoBackup" -framework SwiftUI -framework AppKit -framework CryptoKit
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>AutoBackup</string>
<key>CFBundleIdentifier</key><string>local.sam.autobackup</string>
<key>CFBundleIconFile</key><string>AutoBackup.icns</string>
<key>CFBundleName</key><string>Auto Backup</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.1</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSRemovableVolumesUsageDescription</key><string>Back up files between your selected SD cards and drives.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP"
