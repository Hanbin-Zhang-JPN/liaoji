import AppKit
import ChatCore

extension Workspace {
    func openMediaLibrary() { endProofreading(); preview = false; search = ""; mediaLibrary = true }
    func beginMediaCapture() {
        guard !busy, let shot = currentShot else { return }
        captureShot = shot
    }
    func coveredText(in shot: Screenshot, box: Box) -> [Message] {
        project.messages.filter { m in
            m.sourceID == shot.id && m.media == nil && !m.excluded && m.speaker != .system && m.box.map { box.encloses($0) } == true
        }
    }
    @discardableResult func addMedia(shot: Screenshot, box: Box, kind: MediaKind, speaker: Speaker, caption: String, keywords: String, excludeCovered: Bool) -> Bool {
        guard !busy else { return false }
        guard project.screenshots.contains(where: { $0.id == shot.id }), speaker != .system else { alert = L10n.text("原截图已发生变化，请关闭后重新框选。"); return false }
        guard project.messages.count < Project.maximumMessages, project.messages.filter({ $0.media != nil }).count < Project.maximumMedia else { alert = L10n.text("素材数量已达到上限，请另存后新建项目。"); return false }
        guard !project.messages.contains(where: { $0.media != nil && !$0.excluded && $0.sourceID == shot.id && $0.box == box }) else { alert = L10n.text("这个区域已经保存，可在素材夹中修改说明或分类。"); return false }
        do {
            let crop = try MediaImages.crop(shot, box: box)
            var message = Message(sourceID: shot.id, speaker: speaker, text: caption, box: box)
            message.media = ChatMedia(kind: kind, keywords: keywords, fingerprint: MediaImages.fingerprint(crop))
            var next = project; next.version = 2
            if excludeCovered {
                let ids = Set(coveredText(in: shot, box: box).map(\.id))
                for i in next.messages.indices where ids.contains(next.messages[i].id) { next.messages[i].excluded = true }
            }
            next.insertLocatedMessage(message); next.modified = Date(); ChatParser.markOverlaps(&next)
            commit(next, label: L10n.text("添加聊天素材")); endProofreading(); preview = false; mediaLibrary = true; select(message)
            showNotice(L10n.text("已保存{0}，将随前后文字一起导出。", [String(describing: kind.label)]))
            return true
        } catch { alert = error.localizedDescription; return false }
    }
    func mediaImage(for message: Message) -> NSImage? {
        guard let box = message.box else { return nil }
        let key = "\(message.sourceID?.uuidString ?? "")-\(box.x)-\(box.y)-\(box.width)-\(box.height)" as NSString
        if let image = mediaImageCache.object(forKey: key) { return image }
        guard let cg = try? MediaImages.crop(message, in: project, maximum: 1000) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        mediaImageCache.setObject(image, forKey: key, cost: cg.width * cg.height * 4); return image
    }
    func showMediaSource(_ message: Message) { mediaLibrary = false; preview = false; endProofreading(); search = ""; select(message) }
    func similarMedia(to message: Message) -> [Message] {
        guard let fingerprint = message.media?.fingerprint else { return [] }
        return project.mediaMessages.filter { $0.id != message.id && $0.media?.fingerprint == fingerprint }
    }
    func exportMedia(_ messages: [Message]) {
        guard !busy, !messages.isEmpty else { return }
        let panel = NSOpenPanel(); panel.title = L10n.text("选择素材导出位置"); panel.prompt = L10n.text("导出到这里"); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        do { let result = try MediaImages.export(messages, in: project, to: folder); showNotice(L10n.text("已导出 {0} 份素材和目录", [String(describing: messages.count)])); NSWorkspace.shared.activateFileViewerSelecting([result]) }
        catch { alert = L10n.text("素材导出失败：{0}", [String(describing: error.localizedDescription)]) }
    }
}
