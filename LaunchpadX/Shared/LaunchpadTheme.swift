import SwiftUI

enum LaunchpadTheme {
    static let desktop = Color(red: 7 / 255, green: 16 / 255, blue: 38 / 255)
    static let surface = Color(red: 18 / 255, green: 21 / 255, blue: 33 / 255)
    static let accent = Color(red: 53 / 255, green: 144 / 255, blue: 250 / 255)
    static let violet = Color(red: 154 / 255, green: 73 / 255, blue: 255 / 255)
    static let spacing: CGFloat = 16
    static let iconCornerRadius: CGFloat = 22
    static let cardCornerRadius: CGFloat = 18
    static let searchCornerRadius: CGFloat = 28
    static let editingLongPressDuration: TimeInterval = 1.0

    static let gridSpring = Animation.interactiveSpring(
        response: 0.18,
        dampingFraction: 0.94,
        blendDuration: 0.08
    )
}
