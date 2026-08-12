import Foundation

/// How the chosen art is dressed before it becomes an app icon.
enum IconStyle: String, CaseIterable, Identifiable {
    /// Applied as-is, only squared onto the canvas.
    case original
    /// Clipped to the macOS rounded-square silhouette, with a contact shadow.
    case rounded
    /// Rounded, plus the specular sheen and bevelled rim of the Tahoe look.
    case glass
    /// Rounded, edge to edge, with no shadow or highlight at all.
    case flat

    var id: String { rawValue }

    var label: String {
        switch self {
        case .original: return "Original"
        case .rounded: return "Rounded"
        case .glass: return "Glass"
        case .flat: return "Flat"
        }
    }

    var help: String {
        switch self {
        case .original: return "Use the artwork exactly as it is."
        case .rounded: return "Inset and clipped to the macOS rounded square, with a soft shadow."
        case .glass: return "Rounded, with a glossy highlight and bevelled edge."
        case .flat: return "Rounded and edge to edge — no shadow, no gloss."
        }
    }
}
