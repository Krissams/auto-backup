#!/bin/zsh
set -eu
cd "${0:A:h}/.."
mkdir -p build
xcrun swiftc -target "$(uname -m)-apple-macosx13.0" -swift-version 5 -parse-as-library Sources/BackupProgress.swift Sources/BackupEngine.swift Tests/BackupEngineTests.swift -o build/BackupEngineTests -framework CryptoKit
build/BackupEngineTests
xcrun swiftc -target "$(uname -m)-apple-macosx13.0" -swift-version 5 -parse-as-library Sources/BackupProgress.swift Sources/BackupEngine.swift Sources/DuplicateScanner.swift Tests/DuplicateScannerTests.swift -o build/DuplicateScannerTests -framework CryptoKit
build/DuplicateScannerTests
sed '/^@main/,$d' Sources/AutoBackupApp.swift > build/BackupAppForTests.swift
xcrun swiftc -target "$(uname -m)-apple-macosx13.0" -swift-version 5 -parse-as-library Sources/BackupProgress.swift Sources/BackupEngine.swift Sources/DuplicateScanner.swift Sources/FileReviewSession.swift Sources/DuplicateResultsView.swift Sources/BackupProgressView.swift build/BackupAppForTests.swift Tests/BackupFlowTests.swift -o build/BackupFlowTests -framework SwiftUI -framework AppKit -framework CryptoKit
build/BackupFlowTests
xcrun swiftc -target "$(uname -m)-apple-macosx13.0" -swift-version 5 -parse-as-library Sources/BackupProgress.swift Sources/BackupEngine.swift Sources/DuplicateScanner.swift Sources/FileReviewSession.swift Tests/FileReviewTests.swift -o build/FileReviewTests -framework CryptoKit
build/FileReviewTests
xcrun swiftc -target "$(uname -m)-apple-macosx13.0" -swift-version 5 -parse-as-library Sources/BackupProgress.swift Sources/BackupEngine.swift Tests/BackupProgressTests.swift -o build/BackupProgressTests -framework CryptoKit
build/BackupProgressTests
