// Validate the packaged icon and refresh only this app's Finder registration.
import Foundation
import AppKit
import CoreServices

let appURL = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
if let bundle = Bundle(url: appURL),
   let iconName = bundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String,
   let resources = bundle.resourceURL,
   let icon = NSImage(contentsOf: resources.appendingPathComponent(iconName)),
   !icon.representations.isEmpty {
    print("App icon verified")
} else {
    fatalError("The app bundle is missing a readable application icon")
}

// Hosted CI only validates packaging; registration belongs on the user's Mac.
if ProcessInfo.processInfo.environment["CI"] != "true" {
    try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: appURL.path)
    let status = LSRegisterURL(appURL as CFURL, true)
    if status == noErr {
        NSWorkspace.shared.noteFileSystemChanged(appURL.path)
        NSWorkspace.shared.noteFileSystemChanged(appURL.deletingLastPathComponent().path)
        print("Finder icon registration refreshed")
    } else {
        FileHandle.standardError.write(Data("Note: Finder registration returned \(status); the app and icon were built successfully.\n".utf8))
    }
}
