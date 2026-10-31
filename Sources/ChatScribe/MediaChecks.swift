import AppKit
import PDFKit
import ChatCore

enum MediaChecks {
    @MainActor static func run(folder: URL) throws {
        let directory = folder.appendingPathComponent("media-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = Workspace(dataDirectory: directory)
        defer { model.flush(); try? FileManager.default.removeItem(at: directory) }
        func verify(_ value: Bool, _ label: String) throws { if !value { throw OCRFailure("素材检查失败：" + label) } }
        let shot = try OCRService.prepare(data: fixture(), filename: "图文示例.png")
        let box = Box(x: 0.16, y: 0.24, width: 0.5, height: 0.2)
        var project = Project(); project.title = "图片与表情整理示例"; project.screenshots = [shot]
        let before = Message(sourceID: shot.id, speaker: .other, text: "这是出发前的消息", box: Box(x: 0.15, y: 0.15, width: 0.5, height: 0.04))
        let inside = Message(sourceID: shot.id, speaker: .other, text: "图片里识别出来的文字", box: Box(x: 0.25, y: 0.3, width: 0.3, height: 0.03))
        let after = Message(sourceID: shot.id, speaker: .me, text: "这是收到图片后的消息", box: Box(x: 0.4, y: 0.6, width: 0.4, height: 0.04))
        project.messages = [before, inside, after]
        let url = directory.appendingPathComponent("fixture.liaoji"); try JSONEncoder().encode(project).write(to: url)
        model.loadProject(url)
        let original = model.project
        try verify(model.addMedia(shot: shot, box: box, kind: .picture, speaker: .other, caption: "蓝天与旅行", keywords: "旅行、风景", excludeCovered: false), "保存图片")
        guard let media = model.project.mediaMessages.first else { throw OCRFailure("图片未保存") }
        try verify(model.project.messages.map(\.id) == [before.id, media.id, inside.id, after.id], "按原图位置插入，不破坏前后文")
        try verify(!model.project.messages.first { $0.id == inside.id }!.excluded, "默认不隐藏图片中的 OCR 文字")
        try verify(model.project.version == 2 && (try? model.project.validated()) != nil, "素材项目标记新版本，防止旧软件静默丢失素材")
        try verify(model.mediaImage(for: media) != nil && media.media?.fingerprint != nil, "裁切预览与重复指纹")
        let cropped = try MediaImages.crop(media, in: model.project)
        try verify(abs(Double(cropped.width) - Double(shot.width) * 0.5) < 2 && abs(Double(cropped.height) - Double(shot.height) * 0.2) < 2, "裁切保留原截图区域比例和像素")
        let sky = NSBitmapImageRep(cgImage: cropped).colorAt(x: cropped.width / 8, y: cropped.height / 4)?.usingColorSpace(.deviceRGB)
        try verify(sky != nil && sky!.blueComponent > sky!.redComponent, "裁切读取顶部坐标对应的蓝色图片区")
        try verify(!model.addMedia(shot: shot, box: box, kind: .sticker, speaker: .me, caption: "", keywords: "", excludeCovered: false), "相同截图同一选区不重复插入")
        model.alert = nil; model.undo(); try verify(model.project == original, "素材插入整体撤销")
        model.redo(); try verify(model.project.mediaMessages.first?.id == media.id, "素材插入重做")
        model.undo()
        try verify(model.addMedia(shot: shot, box: box, kind: .picture, speaker: .other, caption: "蓝天与旅行", keywords: "旅行、风景", excludeCovered: true), "主动排除选区内 OCR 文字")
        try verify(model.project.messages.first { $0.id == inside.id }!.excluded, "只排除用户明确选择的文字")
        let first = model.project.mediaMessages[0]
        let stickerBox = Box(x: 0.48, y: 0.68, width: 0.25, height: 0.14)
        try verify(model.addMedia(shot: shot, box: stickerBox, kind: .sticker, speaker: .me, caption: "", keywords: "开心", excludeCovered: false), "无说明表情也能保存与导出")
        let sticker = model.project.mediaMessages[1]
        model.edit(sticker.id) { $0.media?.favorite = true }
        model.startProofreading(from: sticker.id); model.confirmProofreading()
        try verify(model.project.messages.first { $0.id == sticker.id }!.reviewed, "空说明的图片可人工确认")
        model.edit(sticker.id) { $0.media?.favorite = false }
        try verify(model.project.messages.first { $0.id == sticker.id }!.reviewed, "收藏切换不打断已完成的核对")
        model.edit(sticker.id) { $0.media?.favorite = true }
        model.edit(sticker.id) { $0.text = "开心的表情" }
        try verify(!model.project.messages.first { $0.id == sticker.id }!.reviewed, "修改素材说明重置核对")
        let count = model.project.messages.count
        model.mergePrevious(sticker.id); model.split(sticker.id)
        try verify(model.project.messages.count == count, "素材不会被文字合并或拆分破坏")
        model.alert = nil
        let portable = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(model.project)).validated()
        try JSONEncoder().encode(portable).write(to: folder.appendingPathComponent("图文示例项目.liaoji"))
        try verify(portable.mediaMessages.count == 2 && portable.mediaMessages[1].media?.favorite == true, "分类说明关键词收藏完整往返")
        var reocr = portable
        reocr.replaceMessages(for: shot.id, with: [before, after])
        try verify(reocr.mediaMessages.map(\.id) == portable.mediaMessages.map(\.id), "重新 OCR 保留原素材")
        try verify(TextExport.plain(portable).contains("[表情包]") && TextExport.markdown(portable).contains("旅行、风景"), "纯文本保留素材说明及关键词")
        let bundle = try MediaImages.export(portable.mediaMessages, in: portable, to: folder)
        let assets = try FileManager.default.contentsOfDirectory(at: bundle, includingPropertiesForKeys: nil)
        try verify(assets.filter { $0.pathExtension == "png" }.count == 2 && assets.contains { $0.lastPathComponent == "素材目录.md" }, "批量导出 PNG 和素材目录")
        let wordData = try DocumentExporter.data(portable, format: .docx)
        try wordData.write(to: folder.appendingPathComponent("图文素材示例.docx"))
        let word = try NSAttributedString(data: wordData, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: nil)
        let wordFile = folder.appendingPathComponent("图文素材示例.docx")
        let xml = String(data: try unzip(["-p", wordFile.path, "word/document.xml"]), encoding: .utf8) ?? ""
        let imageData = try unzip(["-p", wordFile.path, "word/media/image1.png"])
        _ = try unzip(["-t", wordFile.path])
        try verify(xml.components(separatedBy: "<w:drawing>").count - 1 == 2 && NSImage(data: imageData) != nil && word.string.contains("收到图片后的消息"), "Word 结构含可读取的嵌入图片与前后文字")
        let pdfData = try DocumentExporter.pdf(portable)
        try pdfData.write(to: folder.appendingPathComponent("图文素材示例.pdf"))
        guard let pdf = PDFDocument(data: pdfData) else { throw OCRFailure("图文 PDF 无法打开") }
        try verify(pdf.string?.contains("蓝天与旅行") == true && pdf.string?.contains("开心的表情") == true, "图文 PDF 中文说明")
        try verify(pdfImageCount(pdfData) == 2, "PDF 实际绘制两张图片，而非空占位")
        if let thumbnail = pdf.page(at: 0)?.thumbnail(of: NSSize(width: 900, height: 1273), for: .mediaBox), let tiff = thumbnail.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) { try png.write(to: folder.appendingPathComponent("图文PDF首页.png")) }
        var long = portable
        long.messages = (0..<14).flatMap { index -> [Message] in
            var image = first; image.id = UUID(); image.text = "第 \(index) 张图片"
            return [Message(speaker: .me, text: String(repeating: "聊天正文用于验证图片与文字混排分页。", count: 7)), image]
        }
        let longPDF = try DocumentExporter.pdf(long)
        try longPDF.write(to: folder.appendingPathComponent("图文分页示例.pdf"))
        try verify((PDFDocument(data: longPDF)?.pageCount ?? 0) >= 4 && pdfImageCount(longPDF) == 14, "跨页图片不丢失、不重复")
        model.flush(); let restored = Workspace(dataDirectory: directory)
        try verify(restored.project.mediaMessages.count == 2 && restored.project.mediaMessages[1].media?.favorite == true, "重启保留素材与收藏")
        restored.flush()
        model.removeShot(shot.id); try verify(model.project.mediaMessages.isEmpty, "移除来源截图同时移除关联素材")
        model.undo(); try verify(model.project.mediaMessages.count == 2, "撤销恢复素材与原图")
        let reverse = CropSelection.normalized(start: CGPoint(x: 160, y: 240), end: CGPoint(x: 40, y: 80), size: CGSize(width: 200, height: 400))
        try verify(abs(reverse.x - 0.2) < 0.00001 && abs(reverse.y - 0.2) < 0.00001 && abs(reverse.width - 0.6) < 0.00001 && abs(reverse.height - 0.4) < 0.00001, "反方向框选坐标正确")
        let boundary = CropSelection.normalized(start: CGPoint(x: -20, y: -10), end: CGPoint(x: 220, y: 450), size: CGSize(width: 200, height: 400))
        try verify(boundary.isValid && boundary == Box(x: 0, y: 0, width: 1, height: 1), "框选超出原图时限制在图像边界")
        print("PASS: media crop, context order, optional OCR exclusion, undo/redo, project compatibility and persistence, image/sticker metadata, export folder, DOCX images and multi-page PDF image drawing")
    }
    static func fixture() -> Data {
        let image = NSImage(size: NSSize(width: 750, height: 1624)); image.lockFocus()
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 750, height: 1624).fill()
        NSColor.systemBlue.setFill(); NSRect(x: 100, y: 900, width: 420, height: 360).fill()
        NSColor.systemYellow.setFill(); NSBezierPath(ovalIn: NSRect(x: 250, y: 1040, width: 120, height: 120)).fill()
        NSColor.systemGreen.setFill(); NSBezierPath(roundedRect: NSRect(x: 360, y: 280, width: 190, height: 240), xRadius: 35, yRadius: 35).fill()
        image.unlockFocus()
        return NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    }
    private static func pdfImageCount(_ data: Data) -> Int {
        guard let provider = CGDataProvider(data: data as CFData), let document = CGPDFDocument(provider) else { return 0 }
        let count = ImageCount()
        for index in 1...document.numberOfPages {
            guard let page = document.page(at: index), let pageDictionary = page.dictionary else { continue }
            var resources: CGPDFDictionaryRef?, objects: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(pageDictionary, "Resources", &resources), let resources,
               CGPDFDictionaryGetDictionary(resources, "XObject", &objects), let objects {
                CGPDFDictionaryApplyFunction(objects, { _, value, info in
                    guard let info else { return }
                    var stream: CGPDFStreamRef?
                    guard CGPDFObjectGetValue(value, .stream, &stream), let stream, let dictionary = CGPDFStreamGetDictionary(stream) else { return }
                    var subtype: UnsafePointer<CChar>?
                    if CGPDFDictionaryGetName(dictionary, "Subtype", &subtype), let subtype, String(cString: subtype) == "Image" { Unmanaged<ImageCount>.fromOpaque(info).takeUnretainedValue().value += 1 }
                }, Unmanaged.passUnretained(count).toOpaque())
            }
        }
        return count.value
    }
    private static func unzip(_ arguments: [String]) throws -> Data {
        let process = Process(), output = Pipe(), errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip"); process.arguments = arguments; process.standardOutput = output; process.standardError = errors
        try process.run(); let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw OCRFailure("Word ZIP 内容验证失败") }; return data
    }
}
private final class ImageCount { var value = 0 }
