import AppKit
import CoreText
import ChatCore

enum ExportFormat: String, CaseIterable, Sendable {
    case docx, analysisDocx, pdf, markdown, txt
    var label: String { switch self {
        case .docx: return L10n.text("Word · 阅读收藏")
        case .analysisDocx: return L10n.text("Word · AI 分析")
        case .pdf: return L10n.text("PDF 文档")
        case .markdown: return L10n.text("Markdown · 图文与上下文")
        case .txt: return L10n.text("纯文本")
    } }
    var ext: String { switch self { case .docx, .analysisDocx: return "docx"; case .pdf: return "pdf"; case .markdown: return "md"; case .txt: return "txt" } }
}

enum DocumentExporter {
    private static let senderStartKey = NSAttributedString.Key("LiaojiMediaSenderStart")
    static func attributed(_ p: Project) -> NSAttributedString {
        let result = NSMutableAttributedString()
        func append(_ text: String, size: CGFloat, bold: Bool = false, color: NSColor = .black, space: CGFloat = 10) {
            let style = NSMutableParagraphStyle(); style.paragraphSpacing = space; style.lineSpacing = 5
            result.append(NSAttributedString(string: text + "\n", attributes: [
                .font: bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size),
                .foregroundColor: color, .paragraphStyle: style
            ]))
        }
        append(p.title, size: 26, bold: true, color: NSColor(calibratedRed: 0.12, green: 0.28, blue: 0.25, alpha: 1), space: 16)
        append(L10n.text("参与人：{0}、{1}  ·  {2} 条消息", [String(describing: p.myName), String(describing: p.otherName), String(describing: p.visibleMessages.filter { $0.speaker != .system }.count)]), size: 10, color: .darkGray, space: 16)
        if !p.note.isEmpty { append(p.note, size: 11, color: .darkGray, space: 20) }
        for m in p.visibleMessages {
            if m.speaker == .system { append(m.text, size: 10, color: .darkGray, space: 14) }
            else {
                let senderStart = result.length
                append(p.name(for: m), size: 10, bold: true, color: NSColor(calibratedRed: 0.18, green: 0.40, blue: 0.34, alpha: 1), space: 3)
                if let media = m.media {
                    if let cg = try? MediaImages.crop(m, in: p, maximum: 1000), let png = try? MediaImages.png(cg) {
                        let factor = min(1, 420 / CGFloat(cg.width), 300 / CGFloat(cg.height))
                        let attachment = NSTextAttachment(data: png, ofType: "public.png")
                        attachment.image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                        attachment.bounds = CGRect(x: 0, y: 0, width: CGFloat(cg.width) * factor, height: CGFloat(cg.height) * factor)
                        let location = result.length
                        result.append(NSAttributedString(attachment: attachment))
                        result.addAttribute(senderStartKey, value: senderStart, range: NSRange(location: location, length: 1))
                        append("", size: 12, space: 5)
                    } else { append(L10n.text("[素材图片无法读取]"), size: 11, color: .darkGray) }
                    append(m.text.isEmpty ? "[\(media.kind.label)]" : "[\(media.kind.label)] \(m.text)", size: 11, color: .darkGray, space: 8)
                    if !media.keywords.isEmpty { append(L10n.text("关键词：") + media.keywords, size: 10, color: .darkGray, space: 16) }
                } else { append(m.text, size: 12, space: 16) }
            }
        }
        return result
    }

    static func data(_ project: Project, format: ExportFormat) throws -> Data {
        if format == .docx || format == .analysisDocx { try validateMedia(project) }
        switch format {
        case .txt: return Data(TextExport.plain(project).utf8)
        case .markdown: return Data(TextExport.markdown(project).utf8)
        case .docx:
            return try WordExport.data(project)
        case .analysisDocx:
            return try WordExport.data(project, analysis: true)
        case .pdf: return try pdf(project)
        }
    }

    static func pdf(_ project: Project) throws -> Data {
        try validateMedia(project)
        let text = NSMutableAttributedString(attributedString: attributed(project))
        var images: [Int: (CGImage, CGSize, Int)] = [:]
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let attachment = value as? NSTextAttachment, let image = attachment.image?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
            let size = attachment.bounds.size
            images[range.location] = (image, size, text.attribute(senderStartKey, at: range.location, effectiveRange: nil) as? Int ?? range.location)
            let metrics = Unmanaged.passRetained(PDFImageMetrics(height: size.height, width: size.width)).toOpaque()
            var callbacks = CTRunDelegateCallbacks(version: kCTRunDelegateVersion1, dealloc: { Unmanaged<PDFImageMetrics>.fromOpaque($0).release() }, getAscent: { Unmanaged<PDFImageMetrics>.fromOpaque($0).takeUnretainedValue().height }, getDescent: { _ in 0 }, getWidth: { Unmanaged<PDFImageMetrics>.fromOpaque($0).takeUnretainedValue().width })
            if let delegate = CTRunDelegateCreate(&callbacks, metrics) {
                text.addAttribute(NSAttributedString.Key(kCTRunDelegateAttributeName as String), value: delegate, range: range)
                text.addAttribute(.foregroundColor, value: NSColor.clear, range: range)
            } else { Unmanaged<PDFImageMetrics>.fromOpaque(metrics).release() }
        }
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let data = NSMutableData()
        var media = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
        guard let consumer = CGDataConsumer(data: data as CFMutableData), let context = CGContext(consumer: consumer, mediaBox: &media, nil) else { throw OCRFailure(L10n.text("PDF 创建失败。")) }
        let path = CGPath(rect: CGRect(x: 52, y: 62, width: media.width - 104, height: media.height - 114), transform: nil)
        var offset = 0, page = 1
        while offset < text.length {
            context.beginPDFPage(nil)
            var frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0), path, nil)
            let end = offset + CTFrameGetVisibleStringRange(frame).length
            let cut = images.filter { location, payload in payload.2 >= offset && payload.2 < end && (location >= end || end <= location + 2) }.map { $0.value.2 }.min()
            if let cut, cut > offset { frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: cut - offset), path, nil) }
            CTFrameDraw(frame, context)
            let lines = CTFrameGetLines(frame) as! [CTLine]
            var origins = [CGPoint](repeating: .zero, count: lines.count)
            CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
            for (index, line) in lines.enumerated() {
                let range = CTLineGetStringRange(line)
                for (location, payload) in images where location >= range.location && location < range.location + range.length {
                    let x = CTLineGetOffsetForStringIndex(line, location, nil)
                    context.draw(payload.0, in: CGRect(x: 52 + origins[index].x + x, y: 62 + origins[index].y, width: payload.1.width, height: payload.1.height))
                }
            }
            let footer = NSAttributedString(string: "\(page)", attributes: [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.gray])
            context.textPosition = CGPoint(x: media.width / 2, y: 30)
            CTLineDraw(CTLineCreateWithAttributedString(footer), context)
            context.endPDFPage()
            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 else { throw OCRFailure(L10n.text("PDF 分页失败，请缩短单段内容。")) }
            offset += visible.length; page += 1
        }
        context.closePDF()
        return data as Data
    }
    private static func validateMedia(_ project: Project) throws {
        var bytes = 0, pixels = 0
        for message in project.mediaMessages {
            let image = try MediaImages.crop(message, in: project, maximum: 1000)
            pixels += image.width * image.height; bytes += try MediaImages.png(image).count
            guard bytes <= 80_000_000 && pixels <= 40_000_000 else { throw OCRFailure(L10n.text("本次图文导出的图片总量较大，请分为多个项目导出，或先单独导出素材。")) }
        }
    }
}

private final class PDFImageMetrics {
    let height: CGFloat, width: CGFloat
    init(height: CGFloat, width: CGFloat) { self.height = height; self.width = width }
}
