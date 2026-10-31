import Foundation

public enum ProofreadingScope: String, CaseIterable {
    case pending, attention
    public var label: String { self == .pending ? L10n.text("全部待核对") : L10n.text("需留意") }
}

public enum Proofreading {
    public static func reasons(for message: Message) -> [String] {
        var reasons: [String] = []
        if message.media == nil && message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { reasons.append(L10n.text("文字为空")) }
        if message.confidence < 0.8 { reasons.append(L10n.text("识别不确定")) }
        if message.text.rangeOfCharacter(from: .decimalDigits) != nil { reasons.append(L10n.text("含数字或时间")) }
        if message.text.contains("\u{FFFD}") { reasons.append(L10n.text("可能有未识别字符")) }
        if message.duplicateOf != nil { reasons.append(L10n.text("可能与前图重复")) }
        if message.sourceID == nil || message.box == nil { reasons.append(L10n.text("没有原图定位区域")) }
        return reasons
    }
    public static func queue(in project: Project, scope: ProofreadingScope) -> [Message] {
        project.messages.filter { !$0.excluded && !$0.reviewed && (scope == .pending || !reasons(for: $0).isEmpty) }
    }
    public static func originalText(for message: Message, in project: Project) -> String? {
        guard message.media == nil else { return nil }
        if let original = message.originalText { return original }
        guard let box = message.box, let shot = project.screenshots.first(where: { $0.id == message.sourceID }) else { return nil }
        let lines = shot.lines.filter { box.contains($0.box.x + $0.box.width / 2, $0.box.y + $0.box.height / 2) }
        let text = ChatParser.recognizedText(from: lines)
        return text.isEmpty ? nil : text
    }
}
