import AppKit
import ChatCore

enum WordExport {
    static func data(_ project: Project, analysis: Bool = false) throws -> Data {
        var files: [(String, Data)] = []
        var body = paragraph(project.title, size: 48, bold: true, after: 260, style: "Title")
        body += paragraph(L10n.text(analysis ? "AI 分析材料" : "聊天珍藏"), size: 22, color: "555555", after: 240, style: "Subtitle")
        body += paragraph(L10n.text("参与人：{0}、{1}  ·  {2} 条消息", [project.myName, project.otherName, String(project.visibleMessages.filter { $0.speaker != .system }.count)]), size: 20, color: "555555", after: 120)
        body += paragraph(L10n.text("人工核对：{0} / {1}", [String(project.visibleMessages.filter(\.reviewed).count), String(project.visibleMessages.count)]), size: 20, color: "555555", after: 200)
        if !project.note.isEmpty { body += paragraph(project.note, size: 22, color: "555555", after: 320) }
        body += paragraph(Transcript.readingNote, size: 19, color: "666666", after: 220)
        if analysis { body += paragraph(Transcript.analysisNote, size: 19, color: "666666", after: 220) }
        body += paragraph(L10n.text("聊天原文"), size: 28, bold: true, after: 240, keepNext: true, style: "Heading1")
        var relationships = "", imageIndex = 0
        for entry in Transcript.entries(project) {
            let message = entry.message
            if message.speaker == .system { body += paragraph(entry.number + " · " + message.text, size: 20, color: "555555", after: 240, keepNext: true, style: "System"); continue }
            body += paragraph(entry.number + " · " + project.name(for: message), size: 22, bold: true, after: 60, keepNext: true, style: "Heading2")
            body += paragraph([entry.kindLabel, entry.reviewLabel, entry.source].joined(separator: " · "), size: 18, color: "666666", after: 100, keepNext: true)
            if analysis, let time = entry.nearbyTime { body += paragraph(L10n.text("最近的时间标签：{0}", [time]), size: 18, color: "666666", after: 100, keepNext: true) }
            if let media = message.media {
                imageIndex += 1
                let image = try MediaImages.crop(message, in: project, maximum: 1000)
                files.append(("word/media/image\(imageIndex).png", try MediaImages.png(image)))
                relationships += "<Relationship Id=\"rIdImage\(imageIndex)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/image\(imageIndex).png\"/>"
                let factor = min(1, 420 / CGFloat(image.width), 300 / CGFloat(image.height))
                let width = Int(CGFloat(image.width) * factor * 12700), height = Int(CGFloat(image.height) * factor * 12700)
                body += """
                <w:p><w:pPr><w:keepNext/><w:spacing w:after="100"/></w:pPr><w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="\(width)" cy="\(height)"/><wp:docPr id="\(imageIndex)" name="素材 \(imageIndex)" descr="\(escape(media.kind.label + " " + message.text))"/><wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic><pic:nvPicPr><pic:cNvPr id="\(imageIndex)" name="image\(imageIndex).png"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="rIdImage\(imageIndex)"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(width)" cy="\(height)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>
                """
                body += paragraph(message.documentText, size: 22, color: "555555", after: 320)
            } else { body += paragraph(message.text, size: 24, after: 320) }
        }
        if analysis {
            body += "<w:p><w:pPr><w:pStyle w:val=\"Heading1\"/><w:pageBreakBefore/></w:pPr><w:r><w:t>\(escape(L10n.text("交给 AI 的分析任务")))</w:t></w:r></w:p>"
            body += paragraph(Transcript.analysisNote, size: 21, color: "555555", after: 240)
            for (index, task) in Transcript.analysisTasks.enumerated() { body += paragraph("\(index + 1). " + task, size: 22, after: 260) }
        }
        body += "<w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/><w:pgMar w:top=\"1040\" w:right=\"1040\" w:bottom=\"1200\" w:left=\"1040\" w:header=\"500\" w:footer=\"500\" w:gutter=\"0\"/></w:sectPr>"
        let document = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><w:body>\(body)</w:body></w:document>
        """
        let types = """
        <?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="png" ContentType="image/png"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/></Types>
        """
        files.append(("[Content_Types].xml", Data(types.utf8)))
        files.append(("_rels/.rels", Data("<?xml version=\"1.0\" encoding=\"UTF-8\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>".utf8)))
        relationships += "<Relationship Id=\"rIdStyles\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>"
        files.append(("word/_rels/document.xml.rels", Data("<?xml version=\"1.0\" encoding=\"UTF-8\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\(relationships)</Relationships>".utf8)))
        let styles = """
        <?xml version="1.0" encoding="UTF-8"?><w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:eastAsia="PingFang SC"/><w:sz w:val="24"/><w:color w:val="000000"/></w:rPr></w:rPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:pPr><w:widowControl/><w:spacing w:after="160" w:line="360" w:lineRule="auto"/></w:pPr></w:style><w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:rPr><w:b/><w:sz w:val="48"/><w:color w:val="000000"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Subtitle"><w:name w:val="Subtitle"/><w:basedOn w:val="Normal"/></w:style><w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/><w:outlineLvl w:val="0"/><w:spacing w:before="280" w:after="200"/></w:pPr><w:rPr><w:b/><w:sz w:val="28"/><w:color w:val="000000"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/><w:outlineLvl w:val="1"/></w:pPr><w:rPr><w:b/><w:sz w:val="22"/><w:color w:val="000000"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="System"><w:name w:val="Time and system"/><w:basedOn w:val="Normal"/><w:pPr><w:jc w:val="center"/><w:spacing w:before="180" w:after="180"/></w:pPr></w:style></w:styles>
        """
        files.append(("word/styles.xml", Data(styles.utf8)))
        files.append(("word/document.xml", Data(document.utf8)))
        return StoredZIP.encode(files)
    }
    private static func paragraph(_ text: String, size: Int, bold: Bool = false, color: String = "000000", after: Int, keepNext: Bool = false, style: String = "Normal") -> String {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n").map { "<w:t xml:space=\"preserve\">\(escape($0))</w:t>" }.joined(separator: "<w:br/>")
        return "<w:p><w:pPr><w:pStyle w:val=\"\(style)\"/>\(keepNext ? "<w:keepNext/>" : "")<w:spacing w:after=\"\(after)\" w:line=\"360\" w:lineRule=\"auto\"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii=\"Arial\" w:hAnsi=\"Arial\" w:eastAsia=\"PingFang SC\"/><w:sz w:val=\"\(size)\"/><w:color w:val=\"\(color)\"/>\(bold ? "<w:b/>" : "")</w:rPr>\(lines)</w:r></w:p>"
    }
    private static func escape(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter { s in
            let v = s.value; return v == 9 || v == 10 || v == 13 || (v >= 0x20 && v <= 0xD7FF) || (v >= 0xE000 && v <= 0xFFFD) || (v >= 0x10000 && v <= 0x10FFFF)
        })).replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}

// PNGs are already compressed. Store entries directly to keep export self-contained.
private enum StoredZIP {
    static func encode(_ files: [(String, Data)]) -> Data {
        var result = Data(), central = Data()
        func u16(_ value: UInt16, _ data: inout Data) { var n = value.littleEndian; withUnsafeBytes(of: &n) { data.append(contentsOf: $0) } }
        func u32(_ value: UInt32, _ data: inout Data) { var n = value.littleEndian; withUnsafeBytes(of: &n) { data.append(contentsOf: $0) } }
        for (name, content) in files {
            let filename = Data(name.utf8), size = UInt32(content.count), offset = UInt32(result.count), crc = crc32(content)
            u32(0x04034b50, &result); u16(20, &result); u16(0x800, &result); u16(0, &result); u16(0, &result); u16(0x21, &result)
            u32(crc, &result); u32(size, &result); u32(size, &result); u16(UInt16(filename.count), &result); u16(0, &result)
            result.append(filename); result.append(content)
            u32(0x02014b50, &central); u16(20, &central); u16(20, &central); u16(0x800, &central); u16(0, &central); u16(0, &central); u16(0x21, &central)
            u32(crc, &central); u32(size, &central); u32(size, &central); u16(UInt16(filename.count), &central)
            u16(0, &central); u16(0, &central); u16(0, &central); u16(0, &central); u32(0, &central); u32(offset, &central); central.append(filename)
        }
        let start = UInt32(result.count); result.append(central)
        u32(0x06054b50, &result); u16(0, &result); u16(0, &result); u16(UInt16(files.count), &result); u16(UInt16(files.count), &result)
        u32(UInt32(central.count), &result); u32(start, &result); u16(0, &result)
        return result
    }
    private static let table: [UInt32] = (0..<256).map { value in
        var c = UInt32(value); for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }; return c
    }
    private static func crc32(_ data: Data) -> UInt32 {
        var crc = UInt32.max
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8) }
        return crc ^ UInt32.max
    }
}
