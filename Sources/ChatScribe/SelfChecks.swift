import AppKit
import PDFKit
import ChatCore

enum SelfChecks {
    static func makeIcon(at path: String) throws {
        let folder = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = base * scale
                let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                let factor = CGFloat(pixels) / 1024
                let transform = NSAffineTransform(); transform.scale(by: factor); transform.concat()
                NSColor(calibratedRed: 0.94, green: 0.95, blue: 0.89, alpha: 1).setFill()
                NSBezierPath(roundedRect: NSRect(x: 48, y: 48, width: 928, height: 928), xRadius: 210, yRadius: 210).fill()
                NSColor(calibratedRed: 0.17, green: 0.39, blue: 0.32, alpha: 1).setFill()
                NSBezierPath(roundedRect: NSRect(x: 218, y: 270, width: 600, height: 520), xRadius: 125, yRadius: 125).fill()
                let tail = NSBezierPath(); tail.move(to: NSPoint(x: 320, y: 340)); tail.line(to: NSPoint(x: 300, y: 205)); tail.line(to: NSPoint(x: 445, y: 295)); tail.close(); tail.fill()
                NSColor(calibratedRed: 0.94, green: 0.95, blue: 0.89, alpha: 1).setFill()
                for (index, width) in [370.0, 370.0, 240.0].enumerated() { NSBezierPath(roundedRect: NSRect(x: 330, y: 624 - CGFloat(index) * 105, width: width, height: 29), xRadius: 14, yRadius: 14).fill() }
                NSGraphicsContext.restoreGraphicsState()
                let name = "icon_\(base)x\(base)" + (scale == 2 ? "@2x" : "") + ".png"
                try rep.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name))
            }
        }
    }
    @MainActor static func run() async throws {
        let originalLanguage = L10n.overrideLanguage; L10n.overrideLanguage = .simplifiedChinese
        defer { L10n.overrideLanguage = originalLanguage }
        let args = CommandLine.arguments
        let path = args.firstIndex(of: "--output").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } ?? NSTemporaryDirectory() + "Liaoji-Checks"
        let folder = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if args.contains("--regression-only") {
            try await BugFixChecks.run(folder: folder)
            try Data("PASS\n".utf8).write(to: folder.appendingPathComponent("checks-completed.txt"), options: .atomic)
            return
        }
        try AppearanceChecks.run()
        try await ImportChecks.run(folder: folder)
        try await WorkspaceChecks.run(folder: folder)
        try await ProofreadingChecks.run(folder: folder)
        try MediaChecks.run(folder: folder)
        try LanguageExportChecks.run(folder: folder)
        try await ExportWorkflowChecks.run(folder: folder)
        try await BugFixChecks.run(folder: folder)
        var project = Project(); project.title = "示例 · 周末出行计划"; project.otherName = "小林"
        for i in 0..<2 {
            let data = Demo.screenshot(index: i)
            try data.write(to: folder.appendingPathComponent("screenshot-\(i + 1).png"))
            let shot = try OCRService.recognize(OCRService.prepare(data: data, filename: "示例-\(i + 1).png"))
            project.screenshots.append(shot); project.messages.append(contentsOf: ChatParser.parse(shot))
        }
        let text = project.messages.map(\.text).joined(separator: "\n")
        guard text.contains("公园"), text.contains("相机"), project.messages.contains(where: { $0.speaker == .me }), project.messages.contains(where: { $0.speaker == .other }) else {
            throw OCRFailure("真实 Vision 识别失败：\(text)")
        }
        ChatParser.markOverlaps(&project)
        guard project.messages.filter({ $0.duplicateOf != nil }).count >= 2 else { throw OCRFailure("截图重叠检测失败：\(text)") }
        for i in project.messages.indices where project.messages[i].duplicateOf != nil { project.messages[i].excluded = true }
        let originalAppearance = NSApplication.shared.appearance
        AppearanceMode.dark.apply()
        defer { NSApplication.shared.appearance = originalAppearance }
        let exportText = DocumentExporter.attributed(project)
        if let message = project.messages.first(where: { $0.speaker != .system }) {
            let range = (exportText.string as NSString).range(of: message.text)
            guard range.location != NSNotFound,
                  let color = (exportText.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor)?.usingColorSpace(.deviceRGB),
                  color.redComponent < 0.2 && color.greenComponent < 0.2 && color.blueComponent < 0.2 else { throw OCRFailure("深色界面不应改变导出文档的正文颜色") }
        }
        for format in ExportFormat.allCases {
            let data = try DocumentExporter.data(project, format: format)
            guard data.count > 100 else { throw OCRFailure("\(format) 导出为空") }
            try data.write(to: folder.appendingPathComponent((format == .analysisDocx ? "聊天记录-AI." : "聊天记录.") + format.ext))
            if format == .docx || format == .analysisDocx {
                let result = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: nil)
                guard result.string.contains("公园"), result.string.contains("相机") else { throw OCRFailure("Word 中文往返失败") }
            }
            if format == .pdf {
                guard let pdf = PDFDocument(data: data), pdf.pageCount >= 1, pdf.string?.contains("公园") == true else { throw OCRFailure("PDF 中文提取失败") }
            }
        }
        var long = project
        long.messages = (0..<120).map { i in Message(speaker: i % 2 == 0 ? .me : .other, text: "第 \(i) 条：这是一段用于验证中文分页、标点与长文导出的聊天记录。\n第二行内容应完整保留。") }
        let pdfData = try DocumentExporter.pdf(long)
        guard let pdf = PDFDocument(data: pdfData), pdf.pageCount > 4, pdf.string?.contains("第 119 条") == true else { throw OCRFailure("长 PDF 分页失败") }
        try pdfData.write(to: folder.appendingPathComponent("长文分页.pdf"))
        let archive = try JSONEncoder().encode(project)
        let restored = try JSONDecoder().decode(Project.self, from: archive).validated()
        guard restored.messages == project.messages else { throw OCRFailure("项目保存往返失败") }
        try archive.write(to: folder.appendingPathComponent("示例项目.liaoji"))
        try Data("PASS\n".utf8).write(to: folder.appendingPathComponent("checks-completed.txt"), options: .atomic)
        print("PASS: Vision OCR, bubble grouping, overlap review, DOCX round trip, PDF Chinese extraction, multi-page PDF, Markdown/TXT and portable project")
        print("PASS: exports keep document colors while app appearance is dark")
        print("Artifacts: \(folder.path)")
        print("OCR messages: \(project.messages.count); visible: \(project.visibleMessages.count); long PDF: \(pdf.pageCount) pages")
    }
}
