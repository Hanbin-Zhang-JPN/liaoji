import Foundation

public enum Speaker: String, Codable, CaseIterable, Sendable {
    case other, me, system
    public var label: String { switch self { case .other: return L10n.text("对方"); case .me: return L10n.text("我"); case .system: return L10n.text("时间 / 系统") } }
}

public struct Box: Codable, Equatable, Sendable {
    public var x: Double, y: Double, width: Double, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) { self.x = x; self.y = y; self.width = width; self.height = height }
    public func union(_ b: Box) -> Box {
        let x0 = min(x, b.x), y0 = min(y, b.y)
        return Box(x: x0, y: y0, width: max(x + width, b.x + b.width) - x0, height: max(y + height, b.y + b.height) - y0)
    }
    public func contains(_ px: Double, _ py: Double) -> Bool { px >= x - 0.008 && px <= x + width + 0.008 && py >= y - 0.006 && py <= y + height + 0.006 }
    public func encloses(_ box: Box) -> Bool {
        box.x >= x - 1e-8 && box.y >= y - 1e-8 && box.x + box.width <= x + width + 1e-8 && box.y + box.height <= y + height + 1e-8
    }
    public func overlapsMost(of box: Box) -> Bool {
        let intersection = max(0, min(x + width, box.x + box.width) - max(x, box.x)) * max(0, min(y + height, box.y + box.height) - max(y, box.y))
        return intersection >= min(width * height, box.width * box.height) * 0.5
    }
    public var isValid: Bool {
        [x, y, width, height].allSatisfy(\.isFinite) && x >= 0 && y >= 0 && width > 0 && height > 0 && x + width <= 1.001 && y + height <= 1.001
    }
}

public struct OCRLine: Codable, Equatable, Sendable {
    public var text: String, box: Box, confidence: Float
    public var bubble: Int?, side: Speaker?
    public init(_ text: String, box: Box, confidence: Float = 1, bubble: Int? = nil, side: Speaker? = nil) {
        self.text = text; self.box = box; self.confidence = confidence; self.bubble = bubble; self.side = side
    }
}

public struct Message: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var sourceID: UUID?
    public var speaker: Speaker
    public var text: String
    public var customName: String
    public var originalText: String?
    public var media: ChatMedia?
    public var box: Box?
    public var confidence: Float
    public var reviewed: Bool
    public var excluded: Bool
    public var duplicateOf: UUID?
    public init(sourceID: UUID? = nil, speaker: Speaker, text: String, box: Box? = nil, confidence: Float = 1, reviewed: Bool = false) {
        id = UUID(); self.sourceID = sourceID; self.speaker = speaker; self.text = text; self.box = box; self.confidence = confidence
        self.reviewed = reviewed; excluded = false; duplicateOf = nil; customName = ""; originalText = nil
    }
}

public struct Screenshot: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var filename: String
    public var imageData: Data
    public var width: Int, height: Int
    public var lines: [OCRLine]
    public var top: Double, bottom: Double
    public var error: String?
    public var recognized: Bool
    public init(filename: String, imageData: Data, width: Int, height: Int) {
        id = UUID(); self.filename = filename; self.imageData = imageData; self.width = width; self.height = height
        lines = []; error = nil; recognized = false
        let aspect = Double(height) / Double(max(width, 1))
        top = min(0.12, 0.23 / aspect); bottom = 1 - min(0.10, 0.19 / aspect)
    }
}

public struct Project: Codable, Equatable, Sendable {
    public var version = 1
    public var title = L10n.text("微信聊天记录")
    public var myName = L10n.text("我")
    public var otherName = L10n.text("对方")
    public var note = ""
    public var screenshots: [Screenshot] = []
    public var messages: [Message] = []
    public var modified = Date()
    public static let maximumMessages = 50_000
    public init() {}
    public var visibleMessages: [Message] { messages.filter { !$0.excluded && ($0.media != nil || !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } }
    public func name(for speaker: Speaker) -> String { switch speaker { case .me: return myName; case .other: return otherName; case .system: return L10n.text("时间 / 系统") } }
    public func name(for message: Message) -> String { message.customName.trimmingCharacters(in: .whitespaces).isEmpty ? name(for: message.speaker) : message.customName }
    public mutating func sortMessagesByScreenshotOrder() {
        let order = Dictionary(uniqueKeysWithValues: screenshots.enumerated().map { ($0.element.id, $0.offset) })
        messages = messages.enumerated().sorted {
            let a = $0.element.sourceID.flatMap { order[$0] } ?? Int.max
            let b = $1.element.sourceID.flatMap { order[$0] } ?? Int.max
            return a == b ? $0.offset < $1.offset : a < b
        }.map(\.element)
    }
    public mutating func replaceMessages(for source: UUID, with replacements: [Message]) {
        let retainedMedia = messages.filter { $0.sourceID == source && $0.media != nil }
        let activeRegions = retainedMedia.filter { !$0.excluded }.compactMap(\.box)
        func key(_ message: Message) -> String { (message.originalText ?? message.text).precomposedStringWithCanonicalMapping.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        var hiddenText: [String: [Box]] = [:]
        for message in messages where message.sourceID == source && message.media == nil && message.excluded {
            if let box = message.box, activeRegions.contains(where: { $0.encloses(box) }) { hiddenText[key(message), default: []].append(box) }
        }
        let refreshed = replacements.map { message -> Message in
            var message = message
            if message.media == nil, let box = message.box, activeRegions.contains(where: { $0.encloses(box) }),
               hiddenText[key(message)]?.contains(where: { $0.overlapsMost(of: box) }) == true { message.excluded = true }
            return message
        }
        messages.removeAll { $0.sourceID == source }
        messages.append(contentsOf: refreshed)
        sortMessagesByScreenshotOrder()
        for media in retainedMedia { insertLocatedMessage(media) }
    }
    public func validated() throws -> Project {
        let sourceIDs = Set(screenshots.map(\.id))
        guard (version == 1 || version == 2), screenshots.count <= 300, messages.count <= Self.maximumMessages,
              messages.filter({ $0.media != nil }).count <= Self.maximumMedia,
              screenshots.reduce(0, { $0 + $1.imageData.count }) <= 300_000_000,
              Set(screenshots.map(\.id)).count == screenshots.count,
              Set(messages.map(\.id)).count == messages.count,
              messages.allSatisfy({ message in
                  (message.sourceID.map { sourceIDs.contains($0) } ?? true) && (message.box?.isValid ?? true) && message.confidence.isFinite &&
                  (message.media == nil || (version == 2 && message.sourceID != nil && message.box != nil && message.speaker != .system))
              }),
              screenshots.allSatisfy({ $0.width > 0 && $0.height > 0 && $0.width <= 50_000 && $0.height <= 50_000 && $0.width * $0.height <= 16_000_000 && !$0.imageData.isEmpty && $0.top.isFinite && $0.bottom.isFinite && $0.top >= 0 && $0.bottom <= 1 && $0.bottom - $0.top >= 0.1 && $0.lines.allSatisfy { $0.box.isValid && $0.confidence.isFinite } })
        else { throw ProjectError.invalid }
        return self
    }
}

public enum ProjectError: LocalizedError {
    case invalid
    public var errorDescription: String? { L10n.text("项目格式不正确、版本不兼容，或已超出容量限制。") }
}
