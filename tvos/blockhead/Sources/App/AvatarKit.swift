// Player identity is picked, never typed: an SF Symbol tile + a color.
import SwiftUI

enum AvatarKit {
    static let symbols = [
        "hare.fill", "tortoise.fill", "bird.fill", "ant.fill", "fish.fill",
        "pawprint.fill", "bolt.fill", "star.fill", "moon.stars.fill",
        "flame.fill", "leaf.fill", "crown.fill",
    ]

    static let colors: [Color] = [.purple, .teal, .orange, .pink, .green, .yellow]

    static func symbol(_ index: Int) -> String {
        symbols[((index % symbols.count) + symbols.count) % symbols.count]
    }

    static func color(_ index: Int) -> Color {
        colors[((index % colors.count) + colors.count) % colors.count]
    }
}

// MARK: - Manual selection halo

// Menu screens drive selection through RemoteKit (the `.couchRemote` surface
// owns focus), so slabs get this halo instead of system focus — same look as
// CouchKit's FocusHalo, driven by state.
extension View {
    func selectionHalo(_ isSelected: Bool, cornerRadius: CGFloat = 48) -> some View {
        self
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(isSelected ? 0.35 : 0), lineWidth: 2)
            )
            .scaleEffect(isSelected ? 1.04 : 1.0)
            .shadow(color: .black.opacity(isSelected ? 0.5 : 0), radius: 30, y: 16)
            .animation(.couchFast, value: isSelected)
    }
}
