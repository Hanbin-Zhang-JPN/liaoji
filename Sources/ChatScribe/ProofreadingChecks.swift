import AppKit
import ChatCore

enum ProofreadingChecks {
    @MainActor static func run(folder: URL) async throws {
        let directory = folder.appendingPathComponent("proofreading-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = Workspace(dataDirectory: directory)
        let gate = SnippetGate()
        let asynchronous = Workspace(dataDirectory: directory.appendingPathComponent("async"), snippetRecognizer: { _, _ in try gate.read() })
        defer { model.flush(); asynchronous.flush(); try? FileManager.default.removeItem(at: directory) }
        func verify(_ value: Bool, _ label: String) throws { if !value { throw OCRFailure("核对检查失败：" + label) } }
        func wait(_ condition: () -> Bool) async throws {
            let deadline = Date().addingTimeInterval(60)
            while !condition() && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
            try verify(condition(), "异步操作超时")
        }
        let shot = try OCRService.recognize(OCRService.prepare(data: Demo.screenshot(index: 0), filename: "核对示例.png"))
        var fixture = Project(); fixture.screenshots = [shot]; fixture.messages = ChatParser.parse(shot)
        let file = directory.appendingPathComponent("proof.liaoji")
        try JSONEncoder().encode(fixture).write(to: file)
        guard let first = fixture.messages.first(where: { $0.speaker != .system }), let box = first.box else { throw OCRFailure("核对示例缺少原图位置") }
        model.loadProject(file); model.startProofreading(from: first.id)
        try verify(model.proofMessage?.id == first.id && model.selectedShot == shot.id, "进入核对时原图和消息联动")
        guard let image = model.proofImage(for: first), let imageData = image.tiffRepresentation else { throw OCRFailure("原图局部生成失败") }
        let cropped = try OCRService.prepare(data: imageData, filename: "crop.tiff")
        let cropText = try OCRService.recognizeSnippet(cropped, box: Box(x: 0, y: 0, width: 1, height: 1))
        try verify(cropText.contains("周末"), "放大的原图局部对应当前消息")
        let reread = try OCRService.recognizeSnippet(shot, box: box)
        try verify(reread.contains("周末"), "局部重新识别读取正确区域")
        model.confirmProofreading()
        try verify(model.project.messages.first(where: { $0.id == first.id })?.reviewed == true && model.proofMessage?.id != first.id, "人工确认后前进到下一条")
        model.edit(first.id, coalescing: "text") { $0.text += "修改" }
        try verify(model.project.messages.first(where: { $0.id == first.id })?.reviewed == false, "修改已核对文字会重置核对状态")
        try verify(model.project.messages.first(where: { $0.id == first.id })?.originalText == first.originalText, "修改仍保留初次识别文字")
        model.undo()
        try verify(model.project.messages.first(where: { $0.id == first.id })?.reviewed == true, "撤销修改同时恢复核对状态")
        model.setProofreadingScope(.attention)
        try verify(model.proofreadingQueue.allSatisfy { !Proofreading.reasons(for: $0).isEmpty }, "需留意筛选不混入已核对消息")
        let beforeNavigation = model.proofreadingDone
        model.navigateProofreading(by: 1)
        try verify(model.proofreadingDone == beforeNavigation, "跳过不会自动确认")
        model.setProofreadingScope(.pending)
        for _ in 0..<fixture.messages.count { if model.proofMessage != nil { model.confirmProofreading() } }
        try verify(model.proofreadingPending == 0 && model.proofreadingDone == model.proofreadingTotal, "所有消息只在逐条确认后完成")
        model.flush()
        let reopened = Workspace(dataDirectory: directory)
        try verify(reopened.proofreadingDone == model.proofreadingTotal, "核对进度可以重新打开恢复")
        reopened.flush()
        model.resetProofreadingProgress()
        try verify(model.proofreadingDone == 0, "重置核对进度")
        model.undo(); try verify(model.proofreadingPending == 0, "进度重置可以撤销")
        var digits = fixture
        digits.messages = [Message(sourceID: shot.id, speaker: .me, text: "订了2杯", box: box), Message(sourceID: shot.id, speaker: .other, text: "收到", box: box)]
        let digitsFile = directory.appendingPathComponent("digits.liaoji")
        try JSONEncoder().encode(digits).write(to: digitsFile)
        model.loadProject(digitsFile); model.startProofreading(); model.setProofreadingScope(.attention)
        let numericID = digits.messages[0].id
        model.edit(numericID) { $0.text = "订了两杯" }
        try verify(model.proofMessage?.id == numericID && model.selectedMessage == numericID && model.proofreadingDone == 0, "修正最后一个留意提示后保持当前条目，等待人工确认")
        model.confirmProofreading()
        try verify(model.proofMessage == nil && model.proofreadingPending == 1, "留意条目确认后不会混入普通消息")
        var blank = fixture; blank.messages = [Message(sourceID: shot.id, speaker: .me, text: " \n ")]
        let blankFile = directory.appendingPathComponent("blank.liaoji")
        try JSONEncoder().encode(blank).write(to: blankFile)
        model.loadProject(blankFile); model.startProofreading(); model.confirmProofreading()
        try verify(model.proofreadingDone == 0 && model.project.visibleMessages.isEmpty, "空白不能被确认或导出为有效消息")
        model.excludeProofMessage(); try verify(model.proofreadingTotal == 0, "排除空消息可继续完成")
        model.loadProject(file)
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(fixture)) as! [String: Any]
        legacy["messages"] = (legacy["messages"] as! [[String: Any]]).map { item in var item = item; item.removeValue(forKey: "originalText"); return item }
        let legacyFile = directory.appendingPathComponent("legacy.liaoji")
        try JSONSerialization.data(withJSONObject: legacy).write(to: legacyFile)
        model.loadProject(legacyFile)
        try verify(Proofreading.originalText(for: model.project.messages.first { $0.id == first.id }!, in: model.project)?.contains("周末") == true, "旧版项目可核对原识别文字")
        asynchronous.loadProject(file); asynchronous.startProofreading(from: first.id)
        let originalTexts = asynchronous.project.messages.map(\.text)
        asynchronous.requestSnippetRecognition()
        try await wait { gate.calls == 1 }
        asynchronous.navigateProofreading(by: 1)
        gate.release()
        try await wait { !asynchronous.snippetBusy }
        try verify(asynchronous.snippetCandidate == nil && asynchronous.project.messages.map(\.text) == originalTexts, "切换消息后丢弃迟到的局部结果")
        guard let active = asynchronous.proofMessage else { throw OCRFailure("缺少待核对消息") }
        asynchronous.requestSnippetRecognition()
        try await wait { gate.calls == 2 }
        asynchronous.edit(active.id) { $0.text = "用户手动修改" }
        gate.release()
        try await wait { !asynchronous.snippetBusy }
        try verify(asynchronous.snippetCandidate == nil && asynchronous.currentMessage?.text == "用户手动修改", "等待期间的编辑不会被局部结果覆盖")
        asynchronous.requestSnippetRecognition()
        try await wait { gate.calls == 3 }
        gate.release()
        try await wait { !asynchronous.snippetBusy }
        try verify(asynchronous.snippetCandidate == "候选文字" && asynchronous.currentMessage?.text == "用户手动修改", "局部结果先预览而非自动替换")
        asynchronous.applySnippetCandidate()
        try verify(asynchronous.currentMessage?.text == "候选文字" && asynchronous.currentMessage?.reviewed == false, "采用建议后仍需人工确认")
        asynchronous.undo(); try verify(asynchronous.currentMessage?.text == "用户手动修改", "采用建议可以撤销")
        print("PASS: review crop alignment and OCR, manual confirmations, skip semantics, edit invalidation, progress persistence, empty drafts, legacy baselines and stale snippet isolation")
    }
}

private final class SnippetGate: @unchecked Sendable {
    private let lock = NSLock(), semaphore = DispatchSemaphore(value: 0)
    private var count = 0
    var calls: Int { lock.lock(); defer { lock.unlock() }; return count }
    func read() throws -> String {
        lock.lock(); count += 1; lock.unlock()
        guard semaphore.wait(timeout: .now() + 10) == .success else { throw OCRFailure("局部识别测试等待超时") }
        return "候选文字"
    }
    func release() { semaphore.signal() }
}
