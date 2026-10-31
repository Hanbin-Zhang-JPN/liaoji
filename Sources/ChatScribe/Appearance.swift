import SwiftUI
import AppKit
import ChatCore

enum AppearanceMode: String, CaseIterable {
    case system, light, dark
    var label: String {
        switch self { case .system: return L10n.text("跟随系统"); case .light: return L10n.text("浅色"); case .dark: return L10n.text("深色护眼") }
    }
    var scheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
    @MainActor func apply() {
        switch self {
        case .system: NSApplication.shared.appearance = nil
        case .light: NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case .dark: NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

enum Theme {
    private static func adaptive(_ light: (CGFloat, CGFloat, CGFloat), _ dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let c = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
    static let ink = adaptive((0.16, 0.23, 0.21), (0.85, 0.89, 0.85))
    static let green = adaptive((0.17, 0.39, 0.32), (0.65, 0.79, 0.68))
    static let pale = adaptive((0.89, 0.94, 0.90), (0.18, 0.25, 0.21))
    static let paper = adaptive((0.98, 0.97, 0.94), (0.12, 0.15, 0.135))
    static let canvas = adaptive((0.95, 0.95, 0.92), (0.085, 0.11, 0.098))
    static let muted = adaptive((0.47, 0.52, 0.48), (0.62, 0.68, 0.63))
    static let card = adaptive((1, 1, 1), (0.145, 0.185, 0.16))
}
