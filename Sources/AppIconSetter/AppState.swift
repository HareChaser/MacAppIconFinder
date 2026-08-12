import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    @Published var appURL: URL?
    @Published var appIcon: NSImage?
    @Published var hasCustomIcon = false

    @Published var sourceURL: URL?
    @Published var candidates: [IconCandidate] = []
    @Published var selectedCandidateID: UUID?

    @Published var style: IconStyle = .original
    @Published var restartDockAfterApplying = true

    @Published var status: String = ""
    @Published var statusIsError = false
    @Published var busy = false

    /// The app's own icon, kept aside so a style can be applied to it with no
    /// icon file chosen at all.
    @Published private(set) var appStockIcon: NSImage?
    @Published private(set) var appIconIsStock = true

    var selectedCandidate: IconCandidate? {
        candidates.first { $0.id == selectedCandidateID } ?? candidates.first
    }

    /// What gets styled: the chosen file if there is one, otherwise the app's
    /// own icon.
    var sourceImage: NSImage? { selectedCandidate?.image ?? appStockIcon }

    var isRestylingAppIcon: Bool { selectedCandidate == nil && appStockIcon != nil }

    /// Restyling the app's own icon is only a change if a style is actually
    /// selected — Original over the existing icon would be a no-op.
    var canApply: Bool {
        guard appURL != nil, !busy, sourceImage != nil else { return false }
        return selectedCandidate != nil || style != .original
    }

    var previewImage: NSImage? {
        guard let source = sourceImage else { return nil }
        return IconRenderer.render(source, style: style)
    }

    // MARK: - Picking

    func chooseApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose an application"
        panel.prompt = "Choose"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            setApp(url)
        }
    }

    func chooseIconFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose an icon"
        panel.prompt = "Choose"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = IconLoader.supportedExtensions.compactMap {
            UTType(filenameExtension: $0)
        }
        if panel.runModal() == .OK, let url = panel.url {
            setIconSource(url)
        }
    }

    func setApp(_ url: URL) {
        guard url.pathExtension.lowercased() == "app" else {
            show("Pick an application bundle (.app).", isError: true)
            return
        }
        appURL = url
        appIcon = NSWorkspace.shared.icon(forFile: url.path)
        hasCustomIcon = IconApplier.hasCustomIcon(url)

        let stock = IconLoader.appIcon(for: url, hasCustomIcon: hasCustomIcon)
        appStockIcon = stock.image
        appIconIsStock = stock.isStock

        if !stock.isStock && hasCustomIcon {
            show("\(url.lastPathComponent) already has a custom icon and keeps its stock one in an asset catalogue — a style would stack on top of the current icon. Restore the original first.",
                 isError: true)
        } else {
            show("")
        }
    }

    func clearIconSource() {
        sourceURL = nil
        candidates = []
        selectedCandidateID = nil
        show("")
    }

    func setIconSource(_ url: URL) {
        do {
            let loaded = try IconLoader.load(from: url)
            sourceURL = url
            candidates = loaded
            selectedCandidateID = loaded.first?.id
            show(loaded.count > 1 ? "Found \(loaded.count) icons — pick one below." : "")
        } catch {
            sourceURL = nil
            candidates = []
            selectedCandidateID = nil
            show(error.localizedDescription, isError: true)
        }
    }

    // MARK: - Applying

    func apply() {
        guard let appURL, let source = sourceImage else { return }
        let image = IconRenderer.render(source, style: style)
        let message = isRestylingAppIcon
            ? "\(style.label) style applied to \(appURL.lastPathComponent)'s own icon."
            : "Icon applied to \(appURL.lastPathComponent)."
        write(image, to: appURL, successMessage: message)
    }

    func restoreOriginalIcon() {
        guard let appURL else { return }
        write(nil, to: appURL, successMessage: "Original icon restored for \(appURL.lastPathComponent).")
    }

    private func write(_ image: NSImage?, to appURL: URL, successMessage: String) {
        busy = true
        defer { busy = false }
        do {
            try IconApplier.apply(image, to: appURL)
            finish(appURL, successMessage)
        } catch IconApplier.Error.needsAdministrator {
            guard confirmAdministrator(for: appURL) else {
                show("Cancelled — no changes were made.", isError: false)
                return
            }
            do {
                try IconApplier.applyAsAdministrator(image, to: appURL)
                finish(appURL, successMessage)
            } catch {
                show(error.localizedDescription, isError: true)
            }
        } catch {
            show(error.localizedDescription, isError: true)
        }
    }

    private func finish(_ appURL: URL, _ message: String) {
        hasCustomIcon = IconApplier.hasCustomIcon(appURL)
        appIcon = NSWorkspace.shared.icon(forFile: appURL.path)
        if restartDockAfterApplying { IconApplier.restartDock() }
        show(message)
    }

    private func confirmAdministrator(for appURL: URL) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Administrator password needed"
        alert.informativeText = """
        \(appURL.lastPathComponent) isn't writable by your account. macOS will ask for your password so the icon can be written.
        """
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func show(_ message: String, isError: Bool = false) {
        status = message
        statusIsError = isError
    }
}
