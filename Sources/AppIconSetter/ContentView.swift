import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var state = AppState()

    /// With no icon file chosen, pane 2 previews the app's own icon in the
    /// selected style — so a style can be applied on its own.
    private var iconSubtitle: String {
        if let source = state.sourceURL { return source.lastPathComponent }
        if state.isRestylingAppIcon { return "Styling this app's own icon" }
        return "Drop .ico, .png, .jpg or .exe"
    }

    /// Only offered once a file is chosen, as the way back to restyling the
    /// app's own icon.
    private var clearButton: CardAction? {
        guard state.sourceURL != nil else { return nil }
        return CardAction(title: "Clear", action: state.clearIconSource)
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                DropCard(
                    title: "1 · Application",
                    subtitle: state.appURL?.lastPathComponent ?? "Drop an app here",
                    image: state.appIcon,
                    placeholder: "app.dashed",
                    buttonTitle: "Choose App…",
                    action: state.chooseApp,
                    onDrop: state.setApp
                )

                Image(systemName: "arrow.right")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 90)

                DropCard(
                    title: "2 · Icon",
                    subtitle: iconSubtitle,
                    image: state.previewImage,
                    placeholder: "photo",
                    buttonTitle: "Choose Icon…",
                    action: state.chooseIconFile,
                    onDrop: state.setIconSource,
                    secondaryButton: clearButton
                )
            }

            if state.candidates.count > 1 {
                VariantPicker(candidates: state.candidates,
                              selection: $state.selectedCandidateID)
            }

            HStack(spacing: 16) {
                Picker("Style", selection: $state.style) {
                    ForEach(IconStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help(state.style.help)

                Toggle("Restart Dock after applying", isOn: $state.restartDockAfterApplying)
                    .toggleStyle(.checkbox)
                Spacer()
            }

            Divider()

            HStack(spacing: 12) {
                Text(state.status)
                    .font(.callout)
                    .foregroundStyle(state.statusIsError ? Color.red : Color.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if state.hasCustomIcon {
                    Button("Restore Original", action: state.restoreOriginalIcon)
                        .disabled(state.busy)
                }

                Button("Apply Icon", action: state.apply)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!state.canApply)
            }
        }
        .padding(24)
    }
}

struct CardAction {
    let title: String
    let action: () -> Void
}

private struct DropCard: View {
    let title: String
    let subtitle: String
    let image: NSImage?
    let placeholder: String
    let buttonTitle: String
    let action: () -> Void
    let onDrop: (URL) -> Void
    var secondaryButton: CardAction?

    @State private var targeted = false

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.headline)

            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(style: StrokeStyle(lineWidth: targeted ? 2 : 1, dash: [6, 4]))
                    .foregroundStyle(targeted ? Color.accentColor : Color.secondary.opacity(0.5))

                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 128, height: 128)
                } else {
                    Image(systemName: placeholder)
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(height: 180)
            .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
                loadDroppedURL(from: providers, onDrop)
            }

            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 8) {
                Button(buttonTitle, action: action)
                if let secondaryButton {
                    Button(secondaryButton.title, action: secondaryButton.action)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct VariantPicker: View {
    let candidates: [IconCandidate]
    @Binding var selection: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Icons found in this file")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(candidates) { candidate in
                        let isSelected = (selection ?? candidates.first?.id) == candidate.id
                        VStack(spacing: 4) {
                            Image(nsImage: candidate.image)
                                .resizable()
                                .interpolation(.high)
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 48, height: 48)
                            Text(candidate.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { selection = candidate.id }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Pulls the first file URL out of a drop and hands it back on the main actor.
private func loadDroppedURL(from providers: [NSItemProvider], _ handler: @escaping (URL) -> Void) -> Bool {
    guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) })
    else { return false }

    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
        var url: URL?
        if let data = item as? Data {
            url = URL(dataRepresentation: data, relativeTo: nil)
        } else if let direct = item as? URL {
            url = direct
        }
        guard let url else { return }
        DispatchQueue.main.async { handler(url) }
    }
    return true
}
