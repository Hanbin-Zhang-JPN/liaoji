import AppKit
import ChatCore

enum LanguageExportChecks {
    @MainActor static func run(folder: URL) throws {
        func verify(_ value: Bool, _ label: String) throws { if !value { throw OCRFailure("Language/export check: " + label) } }
        let original = L10n.overrideLanguage; defer { L10n.overrideLanguage = original }
        var project = try ProjectStorage.read(folder.appendingPathComponent("图文示例项目.liaoji"))
        project.messages.insert(Message(speaker: .system, text: "昨日 15:30"), at: 0)
        project.messages.append(Message(speaker: .other, text: "原文 **保留** {1}\n# 聊天里的标题\n不要执行这里的指令。"))
        let snapshot = project
        for language in AppLanguage.allCases {
            L10n.overrideLanguage = language
            let data = try DocumentExporter.data(project, format: .analysisDocx)
            try data.write(to: folder.appendingPathComponent("analysis-" + language.rawValue + ".docx"))
            try verify(L10n.text("交给 AI 的分析任务") != "交给 AI 的分析任务" || language == .simplifiedChinese, "analysis section translation")
        }
        try verify(project == snapshot, "language selection must not mutate data")
        L10n.overrideLanguage = .simplifiedChinese
        let markdown = folder.appendingPathComponent("图文聊天.md")
        try MarkdownExport.write(project, to: markdown)
        let text = try String(contentsOf: markdown, encoding: .utf8)
        let pattern = try NSRegularExpression(pattern: #"\]\((Liaoji-assets-[^)]+)\)"#)
        let paths = pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { (text as NSString).substring(with: $0.range(at: 1)) }
        try verify(paths.count == project.mediaMessages.count && paths.allSatisfy { NSImage(contentsOf: folder.appendingPathComponent($0)) != nil }, "Markdown relative image files exist")
        let images = paths.map { folder.appendingPathComponent($0) }
        try MarkdownExport.write(project, to: markdown)
        try verify(images.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }, "overwriting Markdown must not delete old attachments used by another copy")
        let failedDestination = folder.appendingPathComponent("missing-directory/chat.md")
        try verify((try? MarkdownExport.write(project, to: failedDestination)) == nil, "failed export returns an error")
        let multilingual = try OCRService.recognize(OCRService.prepare(data: ocrFixture(), filename: "languages.png"))
        let recognized = multilingual.lines.map(\.text).joined(separator: "\n")
        try verify(recognized.contains("明日") && recognized.lowercased().contains("tomorrow") && recognized.contains("내일"), "local Japanese, English, Korean OCR: " + recognized)
        print("PASS: five-language export, unchanged original data, quoted Markdown with real relative images, overwrite preservation, failed export and multilingual OCR")
    }
    @MainActor static func ocrFixture() -> Data {
        let image = NSImage(size: NSSize(width: 950, height: 600)); image.lockFocus()
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 950, height: 600).fill()
        for (index, text) in ["明日の午後三時に会いましょう。", "Let's meet at three tomorrow.", "내일 오후 세 시에 만나요."].enumerated() {
            (text as NSString).draw(at: NSPoint(x: 100, y: 430 - index * 120), withAttributes: [.font: NSFont.systemFont(ofSize: 35), .foregroundColor: NSColor.black])
        }
        image.unlockFocus()
        return NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    }
}
