import AppKit
import ChatCore

enum WorkspaceChecks {
    @MainActor static func run(folder: URL) async throws {
        let directory = folder.appendingPathComponent("workspace-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = Workspace(dataDirectory: directory)
        defer { model.flush(); try? FileManager.default.removeItem(at: directory) }
        func verify(_ value: Bool, _ label: String) throws { if !value { throw OCRFailure("工作区检查失败：" + label) } }
        func wait(_ condition: () -> Bool) async throws {
            let deadline = Date().addingTimeInterval(60)
            while !condition() && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
            try verify(condition(), "异步操作超时")
        }
        let a = Demo.screenshot(index: 0), b = Demo.screenshot(index: 1)
        var fixture = Project()
        for i in 0..<3 {
            let shot = try OCRService.prepare(data: i == 1 ? b : a, filename: "截图-\(i).png")
            fixture.screenshots.append(shot)
            fixture.messages.append(Message(sourceID: shot.id, speaker: .other, text: "第一行\n第二行"))
            fixture.messages.append(Message(sourceID: shot.id, speaker: .other, text: "下一条消息"))
        }
        ChatParser.markOverlaps(&fixture)
        let archive = directory.appendingPathComponent("fixture.liaoji")
        try JSONEncoder().encode(fixture).write(to: archive)
        model.loadProject(archive)
        try verify(model.project == fixture && model.undoLabel == nil, "旧项目载入并重置历史：\(model.alert ?? "无错误提示")")
        let ids = fixture.screenshots.map(\.id)
        model.moveShot(ids[0], to: ids[2])
        try verify(model.project.screenshots.map(\.id) == [ids[1], ids[2], ids[0]], "跨多个位置排序")
        try verify(model.project.messages.map(\.sourceID) == [ids[1], ids[1], ids[2], ids[2], ids[0], ids[0]], "消息顺序与截图同步")
        model.undo(); try verify(model.project == fixture, "排序可撤销")
        model.redo(); try verify(model.project.screenshots.last?.id == ids[0], "排序可重做")
        model.undo()
        model.removeShot(ids[0]); try verify(model.project.screenshots.count == 2 && model.project.messages.count == 4, "移除截图与对应记录")
        model.undo(); try verify(model.project == fixture, "移除后原图与消息完整恢复")
        let message = fixture.messages[0].id
        model.edit(message, coalescing: "text") { $0.text = "修改后的内容" }
        model.edit(message, coalescing: "text") { $0.text += "，继续输入" }
        model.undo(); try verify(model.project.messages[0].text == fixture.messages[0].text, "连续输入合并撤销")
        model.redo(); try verify(model.project.messages[0].text.hasSuffix("继续输入"), "重做文字修改")
        model.edit(message) { $0.excluded = true }
        model.undo(); try verify(!model.project.messages[0].excluded && model.project.messages[0].text.hasSuffix("继续输入"), "排除与连续文字编辑分别撤销")
        model.loadProject(archive)
        model.mergePrevious(fixture.messages[1].id)
        try verify(model.project.messages.count == 5, "合并消息")
        model.undo(); try verify(model.project == fixture, "合并恢复完整消息")
        model.edit(message) { $0.excluded = true }
        model.split(message)
        try verify(model.project.messages.prefix(2).allSatisfy(\.excluded), "拆分不重新导出已排除消息")
        model.undo(); model.undo()
        model.edit(fixture.messages[0].id) { $0.customName = "小李" }
        model.edit(fixture.messages[1].id) { $0.customName = "小王" }
        model.mergePrevious(fixture.messages[1].id)
        try verify(model.project.messages.count == 6 && model.alert != nil, "不同群聊署名不可合并")
        model.alert = nil
        var overlap = fixture
        overlap.screenshots = Array(fixture.screenshots.prefix(2))
        overlap.messages = []
        for shot in overlap.screenshots {
            overlap.messages.append(Message(sourceID: shot.id, speaker: .other, text: "第一条完整的重复内容"))
            overlap.messages.append(Message(sourceID: shot.id, speaker: .me, text: "第二条完整的重复内容"))
        }
        let overlapFile = directory.appendingPathComponent("overlap.liaoji")
        try JSONEncoder().encode(overlap).write(to: overlapFile)
        model.loadProject(overlapFile)
        try verify(model.duplicateCount == 2, "载入旧项目时刷新重叠标记")
        model.edit(overlap.messages[0].id) { $0.excluded = true }
        model.hideDuplicateCandidates()
        try verify(!model.project.messages[2].excluded && !model.project.messages[3].excluded, "排除原消息后不误删剩余副本")
        model.loadProject(archive)
        var retry = fixture
        retry.messages.removeAll { $0.sourceID == ids[0] }
        ChatParser.markOverlaps(&retry)
        let retryFile = directory.appendingPathComponent("retry-empty-first.liaoji")
        try JSONEncoder().encode(retry).write(to: retryFile)
        model.loadProject(retryFile); model.selectedShot = ids[0]; model.rebuildSelected()
        try await wait { !model.busy }
        try verify(model.project.messages.first?.sourceID == ids[0] && model.project.messages.last?.sourceID == ids[2], "空截图重试后文字仍按截图顺序排列")
        model.undo(); try verify(model.project == retry, "重新识别的排序修复仍可撤销")
        model.loadProject(archive)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let item = NSPasteboardItem(); item.setData(b, forType: .png)
        board.writeObjects([item])
        model.newProject()
        model.pasteImages(from: board)
        try await wait { !model.busy }
        try verify(model.project.screenshots.count == 1 && !model.project.messages.isEmpty, "粘贴截图并识别")
        model.undo(); try verify(model.project.screenshots.isEmpty && model.project.messages.isEmpty, "整个导入批次一次撤销")
        model.redo(); try verify(model.project.screenshots.count == 1, "重做导入")
        model.importImages([.bytes(b, "同一张.png")])
        try await wait { !model.busy }
        try verify(model.project.screenshots.count == 1 && model.notice?.contains("重复") == true, "重复导入给出反馈")
        model.newProject()
        model.importImages([.bytes(a, "first.png"), .bytes(b, "second.png")])
        model.stopImport()
        try await wait { !model.busy }
        try verify(model.project.screenshots.isEmpty, "停止后不启动后续识别")
        let pending = model.beginReceiving()!
        var cancelled = false
        model.setReceiveCancellation({ cancelled = true }, id: pending)
        model.stopImport()
        model.completeReceiving([.bytes(a, "late.png")], errors: [], id: pending)
        try verify(cancelled && !model.busy && model.project.screenshots.isEmpty, "取消接收后忽略迟到回调")
        model.loadProject(archive); model.flush()
        let restored = Workspace(dataDirectory: directory)
        try verify(restored.project == fixture, "修改后自动保存仍可恢复")
        restored.flush()
        let recoveryDir = directory.appendingPathComponent("recovery-case")
        try FileManager.default.createDirectory(at: recoveryDir, withIntermediateDirectories: true)
        let recoveryURL = recoveryDir.appendingPathComponent("workspace.liaoji")
        var damaged = fixture; damaged.screenshots[0].imageData = Data([1, 2, 3])
        try JSONEncoder().encode(damaged).write(to: recoveryURL)
        try JSONEncoder().encode(fixture).write(to: recoveryURL.appendingPathExtension("previous"))
        let recovered = Workspace(dataDirectory: recoveryDir)
        try verify(recovered.project == fixture && recovered.alert != nil, "截图损坏时回退到有效备份")
        recovered.flush()
        try verify(try ProjectStorage.read(recoveryURL.appendingPathExtension("previous")) == fixture, "恢复后保存不覆盖有效备份")
        let brokenDir = directory.appendingPathComponent("broken-case")
        try FileManager.default.createDirectory(at: brokenDir, withIntermediateDirectories: true)
        let brokenURL = brokenDir.appendingPathComponent("workspace.liaoji")
        let broken = Data("broken primary".utf8), brokenBackup = Data("broken previous".utf8)
        try broken.write(to: brokenURL); try brokenBackup.write(to: brokenURL.appendingPathExtension("previous"))
        let blocked = Workspace(dataDirectory: brokenDir)
        blocked.project.title = "未保存的修改"; blocked.flush()
        try verify(try Data(contentsOf: brokenURL) == broken, "读取失败后暂停写入保护原文件")
        blocked.newProject(); blocked.project.title = "新建后恢复保存"; blocked.flush()
        try verify(try ProjectStorage.read(brokenURL).title == "新建后恢复保存", "读取失败后新建项目可以正常保存")
        let protected = try FileManager.default.contentsOfDirectory(at: brokenDir.appendingPathComponent("Recovery"), includingPropertiesForKeys: nil)
        try verify(try protected.contains { try Data(contentsOf: $0) == brokenBackup }, "新建前保护损坏备份文件")
        print("PASS: workspace undo/redo, typing groups, reordering and transcript order, remove/merge/split recovery, group senders, clipboard OCR, duplicate feedback, batch stop, stale callback protection and persistence")
        print("PASS: stale overlap exclusion, retry order, image-damage fallback, backup preservation and saving new projects after storage failure")
    }
}
