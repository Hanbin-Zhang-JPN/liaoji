import Foundation

public enum AppLanguage: String, CaseIterable, Sendable {
    case simplifiedChinese = "zh-Hans", traditionalChinese = "zh-Hant", japanese = "ja", english = "en", korean = "ko"
    public var name: String {
        switch self { case .simplifiedChinese: return "简体中文"; case .traditionalChinese: return "繁體中文"; case .japanese: return "日本語"; case .english: return "English"; case .korean: return "한국어" }
    }
}

public enum L10n {
    @TaskLocal public static var exportLanguage: AppLanguage?
    private static let state = LanguageOverride()
    public static var overrideLanguage: AppLanguage? {
        get { state.lock.lock(); defer { state.lock.unlock() }; return state.value }
        set { state.lock.lock(); state.value = newValue; state.lock.unlock() }
    }
    public static var language: AppLanguage { exportLanguage ?? overrideLanguage ?? AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "zh-Hans") ?? .simplifiedChinese }
    public static let catalog: [String: [String: String]] = {
        guard let url = Bundle.module.url(forResource: "Translations", withExtension: "json"), let data = try? Data(contentsOf: url), let result = try? JSONDecoder().decode([String: [String: String]].self, from: data) else { return [:] }
        return result
    }()
    public static func text(_ key: String, _ arguments: [String] = []) -> String {
        fill(catalog[key]?[language.rawValue] ?? key, arguments)
    }
    private static func fill(_ template: String, _ arguments: [String]) -> String {
        // Substitute in a single pass so a user's literal “{1}” cannot become another argument.
        let pattern = try! NSRegularExpression(pattern: #"\{(\d+)\}"#)
        var output = template
        for match in pattern.matches(in: template, range: NSRange(template.startIndex..., in: template)).reversed() {
            guard let numberRange = Range(match.range(at: 1), in: template), let number = Int(template[numberRange]), arguments.indices.contains(number), let range = Range(match.range, in: output) else { continue }
            output.replaceSubrange(range, with: arguments[number])
        }
        return output
    }
    private struct Pattern {
        let key: String, order: [Int], regex: NSRegularExpression
    }
    private static let literalKeys: [String: String] = {
        var result: [String: String] = [:]
        for key in catalog.keys.sorted() where !key.contains("{0}") {
            result[key] = key
            for value in catalog[key]?.values ?? Dictionary<String, String>().values { result[value] = key }
        }
        return result
    }()
    private static let storedPatterns: [Pattern] = {
        let placeholder = try! NSRegularExpression(pattern: #"\{(\d+)\}"#)
        var result: [Pattern] = []
        for key in catalog.keys.sorted(by: { $0.count > $1.count }) {
            for template in Set([key] + Array(catalog[key]?.values ?? Dictionary<String, String>().values)) {
                let matches = placeholder.matches(in: template, range: NSRange(template.startIndex..., in: template))
                guard !matches.isEmpty else { continue }
                var pattern = "^", end = template.startIndex, order: [Int] = []
                for match in matches {
                    guard let range = Range(match.range, in: template), let numberRange = Range(match.range(at: 1), in: template), let number = Int(template[numberRange]) else { continue }
                    pattern += NSRegularExpression.escapedPattern(for: String(template[end..<range.lowerBound])) + "(.*?)"
                    order.append(number); end = range.upperBound
                }
                pattern += NSRegularExpression.escapedPattern(for: String(template[end...])) + "$"
                if let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) { result.append(Pattern(key: key, order: order, regex: regex)) }
            }
        }
        return result
    }()
    // For app-generated status/error strings saved before the language changed. Never use on chat content.
    public static func display(_ message: String) -> String {
        if catalog[message] != nil { return text(message) }
        if let key = literalKeys[message] { return text(key) }
        for pattern in storedPatterns {
            guard let match = pattern.regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)) else { continue }
            var arguments = [String](repeating: "", count: (pattern.order.max() ?? -1) + 1)
            for (offset, index) in pattern.order.enumerated() { if let range = Range(match.range(at: offset + 1), in: message) { arguments[index] = String(message[range]) } }
            return text(pattern.key, arguments)
        }
        return message
    }
}

private final class LanguageOverride: @unchecked Sendable {
    let lock = NSLock()
    var value: AppLanguage?
}
