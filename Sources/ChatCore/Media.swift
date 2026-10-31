import Foundation

public enum MediaKind: String, Codable, CaseIterable, Sendable {
    case picture, sticker
    public var label: String { self == .picture ? L10n.text("图片") : L10n.text("表情包") }
    public var symbol: String { self == .picture ? "photo" : "face.smiling" }
}

public struct ChatMedia: Codable, Equatable, Sendable {
    public var kind: MediaKind
    public var keywords: String
    public var favorite: Bool
    public var fingerprint: String?
    public init(kind: MediaKind, keywords: String = "", favorite: Bool = false, fingerprint: String? = nil) {
        self.kind = kind; self.keywords = keywords; self.favorite = favorite; self.fingerprint = fingerprint
    }
}

extension Project {
    public static let maximumMedia = 500
    public var mediaMessages: [Message] { messages.filter { $0.media != nil && !$0.excluded } }
    public mutating func insertLocatedMessage(_ message: Message) {
        if let next = messages.firstIndex(where: { $0.sourceID == message.sourceID && ($0.box?.y ?? 1) > (message.box?.y ?? 1) }) {
            messages.insert(message, at: next)
        } else if let last = messages.lastIndex(where: { $0.sourceID == message.sourceID }) {
            messages.insert(message, at: last + 1)
        } else {
            messages.append(message); sortMessagesByScreenshotOrder()
        }
    }
}

extension Message {
    public var documentText: String {
        guard let media else { return text }
        var content = "[\(media.kind.label)]"
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { content += " " + text }
        if !media.keywords.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { content += L10n.text("\n关键词：") + media.keywords }
        return content
    }
}
