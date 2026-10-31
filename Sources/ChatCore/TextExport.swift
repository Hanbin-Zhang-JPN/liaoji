import Foundation

public enum TextExport {
    public static func plain(_ p: Project) -> String {
        var text = p.title + "\n" + String(repeating: "─", count: 28) + "\n"
        if !p.note.isEmpty { text += p.note + "\n" }
        text += L10n.text("参与人：{0}、{1}", [p.myName, p.otherName]) + "\n\n"
        for m in p.visibleMessages {
            text += m.speaker == .system ? "[\(m.text)]\n\n" : "\(p.name(for: m))\n\(m.documentText)\n\n"
        }
        return text
    }
    public static func escape(_ text: String) -> String {
        var s = text.replacingOccurrences(of: "\\", with: "\\\\")
        for c in ["`", "*", "_", "[", "]", "<", ">", "#", "|", "!"] { s = s.replacingOccurrences(of: c, with: "\\" + c) }
        return s
    }
    public static func markdown(_ p: Project, mediaPaths: [UUID: String] = [:]) -> String {
        var text = "# \(escape(p.title))\n\n"
        if !p.note.isEmpty { text += escape(p.note) + "\n\n" }
        text += escape(L10n.text("参与人：{0}、{1}", [p.myName, p.otherName])) + "\n\n"
        text += escape(Transcript.readingNote) + "\n\n" + escape(Transcript.analysisNote) + "\n\n"
        text += "## " + escape(L10n.text("聊天原文")) + "\n\n"
        for entry in Transcript.entries(p) {
            let m = entry.message
            text += "### \(entry.number) · \(escape(p.name(for: m)))\n\n"
            text += escape(entry.metadata) + "\n\n"
            if let time = entry.nearbyTime, m.speaker != .system { text += escape(L10n.text("最近的时间标签：{0}", [time])) + "\n\n" }
            // Quote every line, including blank lines, so chat text never becomes export metadata.
            text += m.documentText.components(separatedBy: .newlines).map { "> " + escape($0) }.joined(separator: "\n") + "\n\n"
            if let path = mediaPaths[m.id] { text += "![\(escape(m.media?.kind.label ?? L10n.text("图片"))) \(entry.number)](\(path))\n\n" }
        }
        text += "## " + escape(L10n.text("可选的 AI 分析提示")) + "\n\n" + escape(Transcript.analysisNote) + "\n\n"
        for (index, task) in Transcript.analysisTasks.enumerated() { text += "\(index + 1). \(escape(task))\n\n" }
        return text
    }
}
