import AppKit
import ChatCore

extension Workspace {
    var proofreadingQueue: [Message] {
        // Keep an edited item on screen even after its last attention hint is resolved.
        project.messages.filter {
            !$0.excluded && !$0.reviewed && (proofreadingScope == .pending || !Proofreading.reasons(for: $0).isEmpty || $0.id == selectedMessage)
        }
    }
    var proofreadingTotal: Int { project.messages.filter { !$0.excluded }.count }
    var proofreadingDone: Int { project.messages.filter { !$0.excluded && $0.reviewed }.count }
    var proofreadingPending: Int { Proofreading.queue(in: project, scope: .pending).count }
    var proofMessage: Message? { proofreadingQueue.first { $0.id == selectedMessage } ?? proofreadingQueue.first }

    func startProofreading(from id: UUID? = nil) {
        guard !busy else { return }
        invalidateSnippet(); mediaLibrary = false; preview = false; search = ""; proofreadingScope = .pending; proofreading = true
        if let id, let index = project.messages.firstIndex(where: { $0.id == id && !$0.excluded }) {
            if project.messages[index].reviewed {
                var next = project; next.messages[index].reviewed = false; commit(next, label: L10n.text("重新核对消息"))
            }
            select(project.messages[index])
        } else { reconcileProofreadingSelection() }
    }
    func endProofreading() { proofreading = false; proofreadingScope = .pending; invalidateSnippet() }
    func setProofreadingScope(_ scope: ProofreadingScope) {
        proofreadingScope = scope
        if scope == .attention, let current = currentMessage, Proofreading.reasons(for: current).isEmpty { selectedMessage = nil }
        invalidateSnippet(); reconcileProofreadingSelection()
    }
    func reconcileProofreadingSelection() {
        guard proofreading else { return }
        let queue = proofreadingQueue
        if let current = queue.first(where: { $0.id == selectedMessage }) { if let source = current.sourceID { selectedShot = source }; return }
        if let first = queue.first { select(first) } else { selectedMessage = nil }
    }
    func canNavigateProofreading(by delta: Int) -> Bool {
        let queue = proofreadingQueue
        guard let id = proofMessage?.id, let index = queue.firstIndex(where: { $0.id == id }) else { return false }
        return queue.indices.contains(index + delta)
    }
    func navigateProofreading(by delta: Int) {
        guard !busy else { return }
        let queue = proofreadingQueue
        guard let id = proofMessage?.id, let index = queue.firstIndex(where: { $0.id == id }), queue.indices.contains(index + delta) else { return }
        select(queue[index + delta])
    }
    func confirmProofreading() {
        guard !busy, let message = proofMessage, let index = project.messages.firstIndex(where: { $0.id == message.id }) else { return }
        guard message.media != nil || !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { showNotice(L10n.text("这条文字为空，请补充或排除后继续。")); return }
        var next = project; next.messages[index].reviewed = true
        commit(next, label: L10n.text("确认核对"))
        advanceProofreading(after: message.id)
    }
    func excludeProofMessage() {
        guard !busy, let message = proofMessage else { return }
        edit(message.id) { $0.excluded = true }
        advanceProofreading(after: message.id)
    }
    private func advanceProofreading(after id: UUID) {
        let queue = proofreadingQueue
        let positions = Dictionary(uniqueKeysWithValues: project.messages.enumerated().map { ($0.element.id, $0.offset) })
        let position = positions[id] ?? -1
        if let following = queue.first(where: { (positions[$0.id] ?? -1) > position }) ?? queue.first { select(following) }
        else { selectedMessage = nil; invalidateSnippet() }
    }
    func resetProofreadingProgress() {
        guard !busy else { return }
        var next = project
        for index in next.messages.indices { next.messages[index].reviewed = false }
        commit(next, label: L10n.text("重置核对进度"))
        proofreadingScope = .pending; reconcileProofreadingSelection()
    }
    func proofImage(for message: Message) -> NSImage? {
        guard let box = message.box, let shot = project.screenshots.first(where: { $0.id == message.sourceID }) else { return nil }
        if let cached = snippetImageCache, cached.0 == shot.id && cached.1 == box { return cached.2 }
        guard let full = image(for: shot)?.cgImage(forProposedRect: nil, context: nil, hints: nil), let crop = SourceSnippet.crop(full, box: box) else { return nil }
        let image = NSImage(cgImage: crop, size: NSSize(width: crop.width, height: crop.height))
        snippetImageCache = (shot.id, box, image)
        return image
    }
    func invalidateSnippet() {
        snippetRequest = nil; snippetCandidate = nil; snippetError = nil
        // Keep the in-flight worker bounded to one. Its late result will be ignored.
    }
    func requestSnippetRecognition() {
        guard proofreading, !busy, !snippetBusy, let message = proofMessage, message.media == nil, let box = message.box,
              let shot = project.screenshots.first(where: { $0.id == message.sourceID }) else { return }
        select(message)
        let token = UUID(), worker = snippetRecognizer
        snippetRequest = token; snippetWorkerID = token; snippetMessageID = message.id
        snippetCandidate = nil; snippetError = nil; snippetBusy = true
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { Result { try worker(shot, box) } }.value
            guard let self else { return }
            if self.snippetWorkerID == token { self.snippetBusy = false; self.snippetWorkerID = nil; self.snippetMessageID = nil }
            guard self.proofreading, self.snippetRequest == token, self.selectedMessage == message.id,
                  self.project.messages.first(where: { $0.id == message.id })?.text == message.text else { return }
            switch result {
            case .success(let text):
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { self.snippetError = L10n.text("局部未识别出清晰文字，请对照原图手动修正。") }
                else { self.snippetCandidate = text }
            case .failure(let error): self.snippetError = error.localizedDescription
            }
        }
    }
    func applySnippetCandidate() {
        guard proofreading, !busy, !snippetBusy, snippetRequest != nil, let text = snippetCandidate, let message = proofMessage, message.id == selectedMessage else { return }
        if text == message.text { invalidateSnippet(); showNotice(L10n.text("两次识别一致，请继续对照原图确认。")); return }
        edit(message.id) { $0.text = text }
        showNotice(L10n.text("已采用局部识别结果，请对照原图确认。"))
    }
}
