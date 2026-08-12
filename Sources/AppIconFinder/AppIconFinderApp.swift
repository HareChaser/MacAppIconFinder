import AppKit
import SwiftUI

@main
struct Main {
    static func main() {
        let arguments = CommandLine.arguments
        // The elevated copy of this binary re-enters here instead of showing UI.
        if arguments.count > 1, arguments[1] == "--apply-icon" {
            exit(IconApplier.runCommandLine(arguments: arguments))
        }
        // Troubleshooting helper: list the icons in a file and write each one
        // out as a PNG. `AppIconFinder --dump-icons <file> <output-directory>`
        if arguments.count > 3, arguments[1] == "--dump-icons" {
            exit(dumpIcons(source: arguments[2], outputDirectory: arguments[3]))
        }
        AppIconFinderApp.main()
    }
}

private func dumpIcons(source: String, outputDirectory: String) -> Int32 {
    do {
        let candidates = try IconLoader.load(from: URL(fileURLWithPath: source))
        for (index, candidate) in candidates.enumerated() {
            print("\(index): \(candidate.label)")
            let rendered = IconRenderer.render(candidate.image, style: .original)
            guard let data = IconRenderer.pngData(for: rendered) else { continue }
            try data.write(to: URL(fileURLWithPath: outputDirectory)
                .appendingPathComponent("icon-\(index).png"))
        }
        return 0
    } catch {
        FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
        return 1
    }
}

struct AppIconFinderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("AppIconFinder") {
            ContentView()
                .frame(minWidth: 720, minHeight: 520)
        }
        .windowResizability(.contentMinSize)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
