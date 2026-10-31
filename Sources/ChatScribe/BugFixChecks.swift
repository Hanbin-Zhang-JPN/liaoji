import AppKit
import ChatCore

enum BugFixChecks {
    @MainActor static func run(folder: URL) async throws {
        let directory = folder.appendingPathComponent("bug-fixes-" + UUID().uuidString)
        let model = Workspace(dataDirectory: directory)
        defer { model.flush(); try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        func verify(_ condition: Bool, _ label: String) throws { if !condition { throw OCRFailure("回归检查失败：" + label) } }
        func waitForWork() async throws {
            let deadline = Date().addingTimeInterval(60)
            while model.busy && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
            try verify(!model.busy, "异步操作超时")
        }
        func load(_ project: Project, name: String) throws {
            let url = directory.appendingPathComponent(name + ".liaoji")
            try JSONEncoder().encode(project).write(to: url); model.loadProject(url)
            try verify(model.project == project, "载入隔离示例")
        }
        let a = try OCRService.recognize(OCRService.prepare(data: Demo.screenshot(index: 0), filename: "A.png"))
        let b = try OCRService.prepare(data: Demo.screenshot(index: 1), filename: "B.png")
        var c = a; c.id = UUID(); c.filename = "C.png"
        let box = Box(x: 0.15, y: 0.3, width: 0.4, height: 0.04)
        let doneA = Message(sourceID: a.id, speaker: .other, text: "第一条已经核对", box: box, reviewed: true)
        let pendingA = Message(sourceID: a.id, speaker: .me, text: "第二条还没有核对", box: box)
        let doneB = Message(sourceID: b.id, speaker: .me, text: "整张截图均已核对", box: box, reviewed: true)
        let pendingC = Message(sourceID: c.id, speaker: .other, text: "第三张待核对消息", box: box)
        var fixture = Project(); fixture.screenshots = [a, b, c]; fixture.messages = [doneA, pendingA, doneB, pendingC]
        try JSONEncoder().encode(fixture).write(to: folder.appendingPathComponent("核对切换示例.liaoji"))
        try load(fixture, name: "selection")
        model.startProofreading(from: pendingA.id); model.selectScreenshot(a.id)
        try verify(model.selectedMessage == pendingA.id && model.proofMessage?.id == pendingA.id && model.selectedShot == a.id, "切换缩略图跳过已核对的首条消息")
        model.selectScreenshot(b.id)
        try verify(model.selectedMessage == pendingA.id && model.selectedShot == a.id && model.notice != nil, "点击已完成截图时保留核对位置，避免错配原图")
        model.selectScreenshot(c.id)
        try verify(model.selectedMessage == pendingC.id && model.proofMessage?.sourceID == model.selectedShot, "切换到其他待核对截图时原图联动")
        model.removeShot(a.id)
        try verify(model.proofMessage?.id == pendingC.id && model.selectedShot == c.id, "删除截图后重新对齐待核对原图")
        model.undo(); try verify(model.project == fixture && model.proofMessage?.sourceID == model.selectedShot, "撤销删除后保留有效核对位置")
        model.endProofreading(); model.openMediaLibrary()
        model.importImages([.bytes(a.imageData, "重复.png")]); try await waitForWork()
        try verify(model.mediaLibrary, "仅重复导入不打断素材夹")
        model.importImages([.bytes(MediaChecks.fixture(), "新截图.png")]); try await waitForWork()
        try verify(!model.mediaLibrary && model.currentShot?.filename == "新截图.png", "导入新截图后显示新文字而不是旧素材夹")
        model.alert = nil
        var pictureProject = Project(); pictureProject.screenshots = [a]; pictureProject.messages = ChatParser.parse(a)
        try load(pictureProject, name: "media-retry")
        guard let text = pictureProject.messages.first(where: { $0.speaker != .system }), let textBox = text.box else { throw OCRFailure("缺少 OCR 示例消息") }
        try verify(model.addMedia(shot: a, box: textBox, kind: .picture, speaker: .other, caption: "待保留的图片", keywords: "", excludeCovered: true), "保存并排除素材内 OCR 文字")
        let beforeRetry = model.project, imageID = model.project.mediaMessages[0].id
        model.rebuildSelected(); try await waitForWork()
        try verify(model.project.mediaMessages.first?.id == imageID && model.project.messages.contains(where: { $0.media == nil && $0.originalText == text.originalText && $0.excluded }), "重试识别保留素材及其已排除的相同 OCR 文字")
        model.undo(); try verify(model.project == beforeRetry, "重试识别一整步撤销")

        let incomingCount = ChatParser.parse(a).count
        try verify(incomingCount > 1, "容量示例具有多条 OCR 消息")
        var full = Project(); full.version = 2; full.screenshots = [a, b]
        full.messages = (0..<(Project.maximumMessages - incomingCount)).map { _ in Message(sourceID: b.id, speaker: .other, text: "其他截图中的保留消息") }
        var image = Message(sourceID: a.id, speaker: .other, text: "原有素材", box: textBox); image.media = ChatMedia(kind: .picture)
        full.messages.insert(image, at: 0)
        try load(full, name: "capacity")
        model.rebuildSelected(); try await waitForWork()
        try verify(model.project == full && model.alert?.contains("上限") == true && model.undoLabel == nil, "接近上限时把保留素材计入容量，拒绝前保持项目原样")
        model.flush()
        try verify(try ProjectStorage.read(model.dataURL) == full, "容量检查失败后原项目仍能保存和重开")
        model.alert = nil
        try load(fixture, name: "small-final")
        print("PASS: review screenshot selection and removal alignment, duplicate/new import view state, media OCR exclusions and atomic capacity rejection with retained images")
    }
}
