import AppKit
import Foundation

enum IconApplier {
    enum Error: Swift.Error, LocalizedError {
        case needsAdministrator
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .needsAdministrator:
                return "This app is owned by another user, so changing its icon needs an administrator password."
            case .failed(let message):
                return message
            }
        }
    }

    /// Writes `image` as the custom icon of the bundle at `appURL`.
    /// Throws `.needsAdministrator` when the bundle isn't writable by the
    /// current user; the caller decides whether to prompt and retry.
    static func apply(_ image: NSImage?, to appURL: URL) throws {
        guard FileManager.default.isWritableFile(atPath: appURL.path) else {
            throw Error.needsAdministrator
        }
        guard NSWorkspace.shared.setIcon(image, forFile: appURL.path, options: []) else {
            throw Error.failed("macOS refused to write the icon to \(appURL.lastPathComponent).")
        }
        touch(appURL)
    }

    /// Re-runs this same binary as root (macOS shows its own password dialog —
    /// the password is never typed or seen by the app) to do the same write.
    static func applyAsAdministrator(_ image: NSImage?, to appURL: URL) throws {
        let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        var imageArgument = "--none"

        if let image {
            guard let data = IconRenderer.pngData(for: image) else {
                throw Error.failed("Couldn't encode the icon.")
            }
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("AppIconSetter-\(UUID().uuidString).png")
            try data.write(to: temp)
            imageArgument = temp.path
        }

        let command = [executable.path, "--apply-icon", imageArgument, appURL.path]
            .map(shellQuote)
            .joined(separator: " ")
        let source = "do shell script \"\(appleScriptEscape(command))\" with administrator privileges"

        var errorInfo: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let number = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
            if number == -128 {
                throw Error.failed("Cancelled.")
            }
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            throw Error.failed(message)
        }
        touch(appURL)
    }

    /// The entry point used by the elevated copy of this binary.
    static func runCommandLine(arguments: [String]) -> Int32 {
        guard arguments.count >= 4 else { return 2 }
        let imagePath = arguments[2]
        let target = arguments[3]

        var image: NSImage?
        if imagePath != "--none" {
            guard let loaded = NSImage(contentsOfFile: imagePath) else {
                FileHandle.standardError.write(Data("Could not read \(imagePath)\n".utf8))
                return 1
            }
            image = loaded
        }
        let ok = NSWorkspace.shared.setIcon(image, forFile: target, options: [])
        // Only clean up the hand-off file this app wrote — never a file the
        // user happened to point this flag at.
        let handoff = URL(fileURLWithPath: imagePath).lastPathComponent
        if handoff.hasPrefix("AppIconSetter-"), handoff.hasSuffix(".png") {
            try? FileManager.default.removeItem(atPath: imagePath)
        }
        return ok ? 0 : 1
    }

    /// Whether the bundle currently carries a custom icon.
    static func hasCustomIcon(_ appURL: URL) -> Bool {
        let iconFile = appURL.appendingPathComponent("Icon\r")
        if FileManager.default.fileExists(atPath: iconFile.path) { return true }
        let values = try? appURL.resourceValues(forKeys: [.customIconKey])
        return values?.allValues[.customIconKey] as? Bool ?? false
    }

    /// Nudges Finder and the icon services cache so the change shows up now
    /// rather than whenever the bundle is next touched.
    private static func touch(_ url: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        NSWorkspace.shared.noteFileSystemChanged(url.path)
    }

    static func restartDock() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Dock"]
        try? process.run()
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
