import Foundation

public enum ChatParser {
    public static func isTimestamp(_ text: String) -> Bool {
        let patterns = [#"^(?:\d{4}年)?\d{1,2}月\d{1,2}日(?:.*\d{1,2}[:：]\d{2})?$"#,
                        #"^(?:(?:昨天|今天|前天|星期[一二三四五六日天]|周[一二三四五六日天])\s*)?(?:(?:上午|下午|晚上|凌晨|中午|早上)\s*)?\d{1,2}[:：]\d{2}$"#,
                        #"^\d{4}[-/.]\d{1,2}[-/.]\d{1,2}(?:\s+\d{1,2}[:：]\d{2})?$"#,
                        #"^(?:(?:昨日|今日|一昨日|[月火水木金土日]曜日)\s*)?(?:(?:午前|午後)\s*)?\d{1,2}[:：]\d{2}$"#,
                        #"^(?:(?:어제|오늘|그저께|[월화수목금토일]요일)\s*)?(?:(?:오전|오후)\s*)?\d{1,2}[:：]\d{2}$"#,
                        #"^(?:(?:Yesterday|Today|Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)\s*)?(?:(?:AM|PM)\s*)?\d{1,2}:\d{2}(?:\s*(?:AM|PM))?$"#]
        return patterns.contains { text.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }
    }

    public static func parse(_ shot: Screenshot) -> [Message] {
        let filtered = shot.lines.filter { $0.box.y >= shot.top && $0.box.y + $0.box.height <= shot.bottom && $0.box.x + $0.box.width > 0.115 && $0.box.x < 0.895 }
        let lines = readingOrder(filtered)
        var result: [Message] = []
        var lastBubble: Int?
        for line in lines {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let centered = abs(line.box.x + line.box.width / 2 - 0.5) < 0.16
            let system = centered && line.bubble == nil && (isTimestamp(text) || text.contains("撤回了") || text.contains("以下为新消息"))
            let speaker: Speaker = system ? .system : (line.side ?? (line.box.x > 0.45 ? .me : .other))
            if let bubble = line.bubble, bubble == lastBubble, let previous = result.last, previous.speaker == speaker {
                let n = result.count - 1
                let sameRow = abs((previous.box?.y ?? 0) + (previous.box?.height ?? 0) - line.box.y - line.box.height) < line.box.height * 0.45
                result[n].text += (sameRow ? " " : "\n") + text
                result[n].originalText = result[n].text
                result[n].box = previous.box?.union(line.box)
                result[n].confidence = min(previous.confidence, line.confidence)
            } else {
                var message = Message(sourceID: shot.id, speaker: speaker, text: text, box: line.box, confidence: line.side == nil && !system ? min(line.confidence, 0.6) : line.confidence)
                message.originalText = text
                result.append(message)
            }
            lastBubble = line.bubble
        }
        return result
    }

    public static func recognizedText(from lines: [OCRLine]) -> String {
        let ordered = readingOrder(lines)
        var text = "", previous: OCRLine?
        for line in ordered {
            let sameRow = previous.map { abs(($0.box.y + $0.box.height / 2) - (line.box.y + line.box.height / 2)) <= min($0.box.height, line.box.height) * 0.4 } ?? false
            if !text.isEmpty { text += sameRow ? " " : "\n" }
            text += line.text
            previous = line
        }
        return text
    }

    private static func readingOrder(_ lines: [OCRLine]) -> [OCRLine] {
        let vertical = lines.sorted { $0.box.y == $1.box.y ? $0.box.x < $1.box.x : $0.box.y < $1.box.y }
        var result: [OCRLine] = [], row: [OCRLine] = []
        for line in vertical {
            if let anchor = row.first, line.box.y - anchor.box.y > min(anchor.box.height, line.box.height) * 0.4 {
                result.append(contentsOf: row.sorted { $0.box.x < $1.box.x }); row.removeAll(keepingCapacity: true)
            }
            row.append(line)
        }
        result.append(contentsOf: row.sorted { $0.box.x < $1.box.x })
        return result
    }

    private static func normalized(_ text: String) -> String {
        // Preserve punctuation and case: decimals, negation and case-sensitive content matter.
        text.precomposedStringWithCanonicalMapping.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // Only an exact multi-message suffix/prefix overlap is a candidate. Nothing is deleted.
    public static func markOverlaps(_ project: inout Project) {
        for i in project.messages.indices { project.messages[i].duplicateOf = nil }
        let ids = project.screenshots.map(\.id)
        guard ids.count > 1 else { return }
        for pair in zip(ids, ids.dropFirst()) {
            let a = project.messages.indices.filter { project.messages[$0].sourceID == pair.0 && !project.messages[$0].excluded && project.messages[$0].speaker != .system && project.messages[$0].media == nil }
            let b = project.messages.indices.filter { project.messages[$0].sourceID == pair.1 && !project.messages[$0].excluded && project.messages[$0].speaker != .system && project.messages[$0].media == nil }
            let limit = min(a.count, b.count, 30)
            guard limit >= 2 else { continue }
            for length in stride(from: limit, through: 2, by: -1) {
                let left = Array(a.suffix(length)), right = Array(b.prefix(length))
                let matches = zip(left, right).allSatisfy {
                    project.messages[$0].speaker == project.messages[$1].speaker &&
                    project.messages[$0].customName.trimmingCharacters(in: .whitespaces) == project.messages[$1].customName.trimmingCharacters(in: .whitespaces) &&
                    normalized(project.messages[$0].text) == normalized(project.messages[$1].text)
                }
                let characters = right.reduce(0) { $0 + normalized(project.messages[$1].text).count }
                if matches && characters >= 8 {
                    for (l, r) in zip(left, right) { project.messages[r].duplicateOf = project.messages[l].id }
                    break
                }
            }
        }
    }
}
