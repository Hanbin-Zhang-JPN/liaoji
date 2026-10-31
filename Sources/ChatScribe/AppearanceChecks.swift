import SwiftUI
import AppKit

enum AppearanceChecks {
    @MainActor static func run() throws {
        let original = NSApplication.shared.appearance
        defer { NSApplication.shared.appearance = original }
        func brightness(_ color: Color) -> CGFloat {
            var value: CGFloat = 0
            let appearance = NSApplication.shared.appearance ?? NSApplication.shared.effectiveAppearance
            appearance.performAsCurrentDrawingAppearance {
                if let c = NSColor(color).usingColorSpace(.deviceRGB) { value = c.redComponent * 0.2126 + c.greenComponent * 0.7152 + c.blueComponent * 0.0722 }
            }
            return value
        }
        AppearanceMode.dark.apply()
        guard NSApplication.shared.appearance?.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua,
              brightness(Theme.canvas) < 0.2, brightness(Theme.card) < 0.25, brightness(Theme.ink) > 0.7 else { throw OCRFailure("深色主题配色检查失败") }
        AppearanceMode.light.apply()
        guard brightness(Theme.canvas) > 0.8, brightness(Theme.card) > 0.9, brightness(Theme.ink) < 0.3 else { throw OCRFailure("浅色主题配色检查失败") }
        AppearanceMode.system.apply()
        guard NSApplication.shared.appearance == nil else { throw OCRFailure("跟随系统主题检查失败") }
        print("PASS: dark and light semantic colors, readable text contrast and system appearance reset")
    }
}
