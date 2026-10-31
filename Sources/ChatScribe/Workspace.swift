import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ChatCore
import ImageIO

@MainActor final class Workspace: ObservableObject {
    @Published var project = Project() {
        didSet {
            guard oldValue != project else { return }
            if historyEnabled { invalidateSnippet() }
            if historyEnabled && !busy && !restoring {
                history.record(oldValue, label: historyLabel, key: historyKey)
                refreshHistory()
            }
            scheduleSave()
        }
    }
    @Published var selectedShot: UUID?
    @Published var selectedMessage: UUID? { didSet { if oldValue != selectedMessage { invalidateSnippet() } } }
    @Published var busy = false
    @Published var progress = ""
    @Published var status = L10n.text("已保存在本机")
    @Published var alert: String?
    @Published var search = ""
    @Published var showExcluded = false
    @Published var preview = false
    @Published var mediaLibrary = false
    @Published var captureShot: Screenshot?
    let mediaImageCache = NSCache<NSString, NSImage>()
    @Published var zoom: CGFloat = 1
    @Published var dropTargeted = false
    @Published private(set) var undoLabel: String?
    @Published private(set) var redoLabel: String?
    @Published private(set) var stopping = false
    @Published private(set) var batchTotal = 0
    @Published private(set) var notice: String?
    @Published var proofreading = false
    @Published var proofreadingScope = ProofreadingScope.pending
    @Published var snippetBusy = false
    @Published var snippetCandidate: String?
    @Published var snippetError: String?
    var snippetRequest: UUID?
    var snippetWorkerID: UUID?
    var snippetMessageID: UUID?
    var snippetImageCache: (UUID, Box, NSImage)?
    let snippetRecognizer: @Sendable (Screenshot, Box) throws -> String
    private var noticeTask: DispatchWorkItem?
    private let imageCache = NSCache<NSUUID, NSImage>()
    private let thumbnailCache = NSCache<NSUUID, NSImage>()
    private var history = ProjectHistory()
    private var historyEnabled = false
    private var restoring = false
    private var historyLabel = L10n.text("修改文档")
    private var historyKey: String? = "metadata"
    private var receiveCancellation: (() -> Void)?
    private var receiveID: UUID?
    private var saveTask: DispatchWorkItem?
    private let io = DispatchQueue(label: "com.liaoji.persistence")
    private var loadFailed = false
    private var generation = 0
    let dataURL: URL

    init(dataDirectory: URL? = nil, snippetRecognizer: @escaping @Sendable (Screenshot, Box) throws -> String = { try OCRService.recognizeSnippet($0, box: $1) }) {
        self.snippetRecognizer = snippetRecognizer
        let root = dataDirectory ?? ProcessInfo.processInfo.environment["LIAOJI_DATA_DIR"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Liaoji", isDirectory: true)
        dataURL = root.appendingPathComponent("workspace.liaoji")
        do {
            if let loaded = try ProjectStorage.load(dataURL, validate: OCRService.validateImages) {
                project = loaded.project; ChatParser.markOverlaps(&project); selectedShot = project.screenshots.first?.id
                if loaded.recovered { status = L10n.text("已从上一版备份恢复"); alert = L10n.text("当前项目无法读取，已恢复上一版备份。损坏文件已保存在本机数据目录的 Recovery 文件夹中。") }
            }
        } catch { loadFailed = true; status = L10n.text("本机项目读取失败"); alert = L10n.text("本机项目读取失败，已暂停自动保存以保护原文件。可打开其他项目，或新建项目继续；原文件会先备份。\n{0}", [String(describing: error.localizedDescription)]) }
        historyEnabled = true
        imageCache.totalCostLimit = 64_000_000; thumbnailCache.totalCostLimit = 12_000_000
        mediaImageCache.totalCostLimit = 32_000_000
    }

    var currentShot: Screenshot? { project.screenshots.first { $0.id == selectedShot } }
    var currentMessage: Message? { project.messages.first { $0.id == selectedMessage } }
    var duplicateCount: Int { project.messages.filter { !$0.excluded && $0.duplicateOf != nil }.count }
    var canStop: Bool { busy && !stopping && (batchTotal > 0 || receiveCancellation != nil) }
    func image(for shot: Screenshot, thumbnail: Bool = false) -> NSImage? {
        let cache = thumbnail ? thumbnailCache : imageCache, key = shot.id as NSUUID
        if let cached = cache.object(forKey: key) { return cached }
        let image: NSImage?
        if thumbnail, let source = CGImageSourceCreateWithData(shot.imageData as CFData, nil),
           let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 160] as CFDictionary) {
            image = NSImage(cgImage: cg, size: .zero)
        } else { image = NSImage(data: shot.imageData) }
        if let image { cache.setObject(image, forKey: key, cost: thumbnail ? 100_000 : shot.width * shot.height * 4) }
        return image
    }
    func showNotice(_ text: String) {
        noticeTask?.cancel(); notice = text
        let work = DispatchWorkItem { [weak self] in self?.notice = nil }
        noticeTask = work; DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    private func refreshHistory() { undoLabel = history.undoLabel; redoLabel = history.redoLabel }
    private func resetHistory() {
        history.clear(); refreshHistory(); noticeTask?.cancel(); notice = nil
        imageCache.removeAllObjects(); thumbnailCache.removeAllObjects()
        endProofreading(); snippetImageCache = nil
        mediaLibrary = false; captureShot = nil; mediaImageCache.removeAllObjects()
    }
    func commit(_ next: Project, label: String) {
        let previousLabel = historyLabel, previousKey = historyKey
        historyLabel = label; historyKey = nil; project = next
        historyLabel = previousLabel; historyKey = previousKey
    }
    private func checkpoint(_ label: String) { history.record(project, label: label); refreshHistory() }
    func undo() {
        let label = history.undoLabel ?? L10n.text("操作")
        guard !busy, let previous = history.undo(current: project) else { return }
        restoring = true; project = previous; restoring = false; reconcileSelection(); refreshHistory()
        showNotice(L10n.text("已撤销 {0}", [L10n.display(label)]))
    }
    func redo() {
        let label = history.redoLabel ?? L10n.text("操作")
        guard !busy, let next = history.redo(current: project) else { return }
        restoring = true; project = next; restoring = false; reconcileSelection(); refreshHistory()
        showNotice(L10n.text("已重做 {0}", [L10n.display(label)]))
    }
    private func reconcileSelection() {
        if !project.screenshots.contains(where: { $0.id == selectedShot }) { selectedShot = project.screenshots.first?.id }
        if !project.messages.contains(where: { $0.id == selectedMessage }) { selectedMessage = nil }
        if let source = currentMessage?.sourceID { selectedShot = source }
        reconcileProofreadingSelection()
    }
    func beginReceiving() -> UUID? {
        guard !busy else { return nil }
        let id = UUID(); receiveID = id; busy = true; stopping = false; progress = L10n.text("正在接收图片…"); return id
    }
    func setReceiveCancellation(_ cancel: @escaping () -> Void, id: UUID) { if receiveID == id { receiveCancellation = cancel; objectWillChange.send() } }
    func completeReceiving(_ inputs: [ImageInput], errors: [String], id: UUID) {
        guard receiveID == id else { return }
        receiveID = nil; receiveCancellation = nil
        importImages(inputs, receiving: true, initialErrors: errors)
    }
    func rejectReceiving(id: UUID) {
        guard receiveID == id else { return }
        receiveID = nil; receiveCancellation = nil; busy = false; progress = ""
    }
    func stopImport() {
        if let cancel = receiveCancellation {
            receiveID = nil; receiveCancellation = nil; cancel()
            busy = false; stopping = false; progress = ""; showNotice(L10n.text("已取消接收图片"))
        } else if busy && batchTotal > 0 { stopping = true; progress = L10n.text("处理完当前截图后停止…") }
    }
    func pasteImages(from board: NSPasteboard = .general) {
        guard !busy else { return }
        guard PhotoDropReader.canRead(board) else { alert = L10n.text("剪贴板中没有图片。可先在“照片”中复制截图，再选择“粘贴截图”。"); return }
        guard let id = beginReceiving() else { return }
        if !PhotoDropReader.receive(board, cancellation: { [weak self] cancel in self?.setReceiveCancellation(cancel, id: id) }, completion: { [weak self] images, errors in self?.completeReceiving(images, errors: errors, id: id) }) {
            rejectReceiving(id: id); alert = L10n.text("无法读取剪贴板图片，请重新复制截图。")
        }
    }

    private func scheduleSave() {
        guard historyEnabled && !loadFailed else { return }
        saveTask?.cancel(); generation += 1; status = L10n.text("正在保存…")
        let work = DispatchWorkItem { [weak self] in self?.persist() }
        saveTask = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    func persist() {
        guard !loadFailed else { return }
        saveTask?.cancel(); generation += 1
        let snapshot = project, url = dataURL, g = generation
        io.async { [weak self] in
            do {
                try ProjectStorage.save(snapshot, to: url, validate: OCRService.validateImages)
                DispatchQueue.main.async { [weak self] in if self?.generation == g { self?.status = L10n.text("已保存在本机") } }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard self?.generation == g else { return }
                    self?.status = L10n.text("保存失败"); self?.alert = L10n.text("保存失败：{0}", [String(describing: error.localizedDescription)])
                }
            }
        }
    }

    func flush() { persist(); io.sync {} }

    func chooseImages() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.title = L10n.text("导入微信截图"); panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .bmp, .image]
        if panel.runModal() == .OK { importURLs(panel.urls) }
    }

    func importURLs(_ urls: [URL]) {
        let sorted = urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        importImages(sorted.map { .file($0) })
    }

    func importImages(_ inputs: [ImageInput], receiving: Bool = false, initialErrors: [String] = []) {
        guard (!busy || receiving), !inputs.isEmpty else {
            if receiving { busy = false; progress = ""; alert = initialErrors.isEmpty ? L10n.text("未收到图片，请重新拖入。") : initialErrors.joined(separator: "\n") }
            return
        }
        busy = true; preview = false; stopping = false; batchTotal = inputs.count
        Task {
            var failures = initialErrors
            var imported = 0, skipped = 0
            for (index, input) in inputs.enumerated() {
                if stopping { break }
                progress = L10n.text("识别截图 {0} / {1}", [String(describing: index + 1), String(describing: inputs.count)])
                do {
                    let prepared = try await Task.detached(priority: .userInitiated) {
                        try input.prepare()
                    }.value
                    guard project.screenshots.count < 300, project.screenshots.reduce(0, { $0 + $1.imageData.count }) + prepared.imageData.count <= 300_000_000 else { throw OCRFailure(L10n.text("项目容量已满，请保存当前项目后新建项目。")) }
                    guard !project.screenshots.contains(where: { $0.imageData == prepared.imageData }) else { skipped += 1; continue }
                    if imported == 0 { checkpoint(L10n.text("导入截图")); endProofreading(); mediaLibrary = false }
                    project.screenshots.append(prepared); selectedShot = prepared.id
                    selectedMessage = nil
                    imported += 1
                    do {
                        let recognized = try await Task.detached(priority: .userInitiated) { try OCRService.recognize(prepared) }.value
                        let parsed = ChatParser.parse(recognized)
                        guard project.messages.count + parsed.count <= Project.maximumMessages else { throw OCRFailure(L10n.text("消息数量已达到项目上限，请另存当前项目后新建。原截图已保留。")) }
                        if let i = project.screenshots.firstIndex(where: { $0.id == prepared.id }) { project.screenshots[i] = recognized }
                        project.messages.append(contentsOf: parsed)
                        selectedShot = prepared.id; selectedMessage = parsed.first?.id
                        if let error = recognized.error { failures.append("\(prepared.filename)：\(error)") }
                    } catch {
                        if let i = project.screenshots.firstIndex(where: { $0.id == prepared.id }) { project.screenshots[i].error = error.localizedDescription }
                        failures.append("\(prepared.filename)：\(error.localizedDescription)")
                    }
                } catch { failures.append(error.localizedDescription) }
            }
            ChatParser.markOverlaps(&project)
            let wasStopped = stopping
            busy = false; stopping = false; batchTotal = 0; progress = ""; persist()
            showNotice((wasStopped ? L10n.text("已停止 · ") : "") + L10n.text("导入 {0} 张", [String(describing: imported)]) + (skipped > 0 ? L10n.text(" · 跳过 {0} 张重复图片", [String(describing: skipped)]) : ""))
            if !failures.isEmpty { alert = failures.joined(separator: "\n") }
        }
    }

    func selectScreenshot(_ id: UUID) {
        guard !busy, project.screenshots.contains(where: { $0.id == id }) else { return }
        let messages = project.messages.filter { $0.sourceID == id && !$0.excluded }
        if proofreading {
            if let pending = messages.first(where: { !$0.reviewed }) { select(pending) }
            else if !proofreadingQueue.isEmpty { showNotice(L10n.text("这张截图没有待核对消息，已保留当前核对位置。")) }
            else { selectedShot = id; selectedMessage = nil }
        } else {
            selectedShot = id; selectedMessage = messages.first?.id
        }
    }

    func select(_ message: Message) {
        guard let m = project.messages.first(where: { $0.id == message.id }) else { return }
        if proofreading {
            guard !m.excluded && !m.reviewed else { return }
            if proofreadingScope == .attention && selectedMessage != m.id && Proofreading.reasons(for: m).isEmpty { proofreadingScope = .pending }
        } else if m.excluded { showExcluded = true }
        if selectedMessage != m.id { history.endCoalescing() }
        selectedMessage = m.id; if let source = m.sourceID { selectedShot = source }
    }

    func edit(_ id: UUID, coalescing: String? = nil, _ change: (inout Message) -> Void) {
        guard !busy, let i = project.messages.firstIndex(where: { $0.id == id }) else { return }
        var next = project
        change(&next.messages[i])
        if next.messages[i].media != nil && next.messages[i].speaker == .system { next.messages[i].speaker = project.messages[i].speaker }
        guard next.messages[i] != project.messages[i] else { return }
        if next.messages[i].text != project.messages[i].text || next.messages[i].speaker != project.messages[i].speaker || next.messages[i].customName != project.messages[i].customName || next.messages[i].media?.kind != project.messages[i].media?.kind || next.messages[i].box != project.messages[i].box { next.messages[i].reviewed = false }
        ChatParser.markOverlaps(&next)
        next.modified = Date()
        let previousLabel = historyLabel, previousKey = historyKey
        historyLabel = coalescing == "text" ? L10n.text("修改文字") : (coalescing == "name" ? L10n.text("修改署名") : L10n.text("修改消息"))
        historyKey = coalescing.map { "message-" + id.uuidString + "-" + $0 }
        project = next; historyLabel = previousLabel; historyKey = previousKey
    }

    func moveShot(_ id: UUID, by delta: Int) {
        guard !busy, let i = project.screenshots.firstIndex(where: { $0.id == id }), project.screenshots.indices.contains(i + delta) else { return }
        moveShot(id, to: project.screenshots[i + delta].id)
    }

    func moveShot(_ id: UUID, to target: UUID) {
        guard !busy, id != target, let from = project.screenshots.firstIndex(where: { $0.id == id }), let to = project.screenshots.firstIndex(where: { $0.id == target }) else { return }
        var next = project
        let shot = next.screenshots.remove(at: from); next.screenshots.insert(shot, at: to)
        next.sortMessagesByScreenshotOrder()
        ChatParser.markOverlaps(&next); commit(next, label: L10n.text("调整截图顺序"))
    }

    func removeShot(_ id: UUID) {
        guard !busy else { return }
        var next = project
        next.screenshots.removeAll { $0.id == id }; next.messages.removeAll { $0.sourceID == id }
        ChatParser.markOverlaps(&next); commit(next, label: L10n.text("移除截图"))
        if selectedShot == id { selectedShot = project.screenshots.first?.id }
        selectedMessage = nil
        reconcileSelection()
    }

    func rebuildSelected() {
        guard !busy, let shot = currentShot else { return }
        busy = true; progress = L10n.text("重新识别当前截图…")
        Task {
            do {
                let recognized = try await Task.detached(priority: .userInitiated) { try OCRService.recognize(shot) }.value
                let parsed = ChatParser.parse(recognized)
                var next = project
                if let i = next.screenshots.firstIndex(where: { $0.id == shot.id }) { next.screenshots[i] = recognized }
                next.replaceMessages(for: shot.id, with: parsed)
                guard next.messages.count <= Project.maximumMessages else { throw OCRFailure(L10n.text("重新识别将超出消息数量上限，原有内容已保留。")) }
                ChatParser.markOverlaps(&next); next.modified = Date()
                checkpoint(L10n.text("重新识别截图"))
                project = next; selectedMessage = nil; reconcileSelection()
            } catch { alert = error.localizedDescription }
            busy = false; progress = ""
        }
    }

    func addMessage() {
        guard !busy else { return }
        guard project.messages.count < Project.maximumMessages else { alert = L10n.text("消息数量已达到项目上限，请另存后新建项目。"); return }
        var next = project
        let m = Message(sourceID: selectedShot, speaker: .other, text: "")
        if let id = selectedMessage, let i = next.messages.firstIndex(where: { $0.id == id }) { next.messages.insert(m, at: i + 1) }
        else if let last = next.messages.lastIndex(where: { $0.sourceID == selectedShot }) { next.messages.insert(m, at: last + 1) }
        else { next.messages.append(m) }
        commit(next, label: L10n.text("补充消息"))
        select(m); preview = false; mediaLibrary = false
    }

    func mergePrevious(_ id: UUID) {
        guard !busy, let i = project.messages.firstIndex(where: { $0.id == id }), i > 0 else { return }
        let m = project.messages[i], prev = project.messages[i - 1]
        guard m.media == nil && prev.media == nil else { alert = L10n.text("图片与表情保留为独立消息，请在说明中补充文字。"); return }
        guard m.sourceID == prev.sourceID, m.speaker == prev.speaker, project.name(for: m) == project.name(for: prev), !prev.excluded, !m.excluded else { alert = L10n.text("只能合并同一张截图中、同一说话人的相邻记录。"); return }
        var next = project
        let previousOriginal = Proofreading.originalText(for: prev, in: project), currentOriginal = Proofreading.originalText(for: m, in: project)
        next.messages[i - 1].text += "\n" + m.text
        if prev.box == m.box && (prev.originalText == nil || m.originalText == nil) && previousOriginal == currentOriginal {
            next.messages[i - 1].originalText = previousOriginal
        } else { next.messages[i - 1].originalText = previousOriginal.flatMap { a in currentOriginal.map { a + "\n" + $0 } } }
        if let a = prev.box, let b = m.box { next.messages[i - 1].box = a.union(b) }
        next.messages[i - 1].reviewed = false
        next.messages[i - 1].duplicateOf = nil
        next.messages.remove(at: i); ChatParser.markOverlaps(&next); commit(next, label: L10n.text("合并消息")); selectedMessage = prev.id
    }

    func split(_ id: UUID) {
        guard !busy, let i = project.messages.firstIndex(where: { $0.id == id }) else { return }
        let m = project.messages[i], lines = m.text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard m.media == nil else { return }
        guard lines.count > 1 else { return }
        guard project.messages.count - 1 + lines.count <= Project.maximumMessages else { alert = L10n.text("拆分将超出消息数量上限，原有消息已保留。"); return }
        let originals = m.originalText?.components(separatedBy: .newlines).filter { !$0.isEmpty }
        let replacements = lines.enumerated().map { index, text -> Message in
            var item = Message(sourceID: m.sourceID, speaker: m.speaker, text: text, box: m.box, confidence: m.confidence)
            if let originals, originals.count == lines.count { item.originalText = originals[index] }
            item.customName = m.customName; item.excluded = m.excluded; return item
        }
        var next = project; next.messages.replaceSubrange(i...i, with: replacements); ChatParser.markOverlaps(&next); commit(next, label: L10n.text("拆分消息"))
        selectedMessage = replacements.first?.id
    }

    func hideDuplicateCandidates() {
        guard !busy else { return }
        var next = project
        ChatParser.markOverlaps(&next)
        for i in next.messages.indices where next.messages[i].duplicateOf != nil { next.messages[i].excluded = true }
        commit(next, label: L10n.text("排除重复消息"))
    }

    func newProject() {
        guard !busy else { return }
        do { try protectFailedStorage(); try archiveCurrent() } catch { alert = L10n.text("备份当前项目失败，尚未新建：{0}", [String(describing: error.localizedDescription)]); return }
        restoring = true; project = Project(); restoring = false; resetHistory()
        selectedShot = nil; selectedMessage = nil; search = ""; preview = false
    }

    private func protectFailedStorage() throws {
        guard loadFailed else { return }
        try ProjectStorage.protectExistingFiles(dataURL)
        loadFailed = false
    }

    private func archiveCurrent() throws {
        guard !project.messages.isEmpty || !project.screenshots.isEmpty else { return }
        let folder = dataURL.deletingLastPathComponent().appendingPathComponent("Archives")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let name = "\(stamp)-\(UUID().uuidString.prefix(6)).liaoji"
        try JSONEncoder().encode(project).write(to: folder.appendingPathComponent(name), options: .atomic)
    }

    func showDataFolder() { NSWorkspace.shared.open(dataURL.deletingLastPathComponent()) }

    func loadDemo() {
        guard !busy else { return }
        do { try protectFailedStorage(); try archiveCurrent() } catch { alert = error.localizedDescription; return }
        var p = Project(); p.title = L10n.text("示例 · 周末出行计划"); p.myName = L10n.text("我"); p.otherName = L10n.text("小林"); p.note = L10n.text("这是一份虚构示例，用于体验截图识别、原图校对和文档导出。")
        restoring = true; project = p; restoring = false; resetHistory(); busy = true; preview = false
        Task {
            for index in 0..<2 {
                progress = L10n.text("识别示例截图 {0} / 2", [String(describing: index + 1)])
                do {
                    let data = Demo.screenshot(index: index)
                    let shot = try await Task.detached(priority: .userInitiated) {
                        try OCRService.recognize(OCRService.prepare(data: data, filename: L10n.text("示例截图-{0}.png", [String(describing: index + 1)])))
                    }.value
                    project.screenshots.append(shot); project.messages.append(contentsOf: ChatParser.parse(shot)); selectedShot = shot.id
                } catch { alert = error.localizedDescription }
            }
            ChatParser.markOverlaps(&project); selectedShot = project.screenshots.first?.id; busy = false; progress = ""
        }
    }

    func saveProject() {
        let panel = NSSavePanel(); panel.title = L10n.text("保存完整项目（含截图和校对内容）")
        panel.nameFieldStringValue = project.title + ".liaoji"; panel.allowedContentTypes = [UTType(filenameExtension: "liaoji") ?? .data]
        if panel.runModal() == .OK, let url = panel.url {
            do { try JSONEncoder().encode(project).write(to: url, options: .atomic); status = L10n.text("项目副本已保存") }
            catch { alert = error.localizedDescription }
        }
    }

    func openProject() {
        let panel = NSOpenPanel(); panel.title = L10n.text("打开聊迹项目"); panel.allowedContentTypes = [UTType(filenameExtension: "liaoji") ?? .data, .json]
        if panel.runModal() == .OK, let url = panel.url { loadProject(url) }
    }

    func loadProject(_ url: URL) {
        guard !busy else { return }
        do {
            var loaded = try ProjectStorage.read(url)
            try OCRService.validateImages(in: loaded)
            ChatParser.markOverlaps(&loaded)
            if !loadFailed { try archiveCurrent(); flush() } else { try protectFailedStorage() }
            loadFailed = false; restoring = true; project = loaded; restoring = false; resetHistory()
            selectedShot = loaded.screenshots.first?.id; selectedMessage = nil
            search = ""; preview = false
        } catch { alert = L10n.text("无法打开项目：{0}", [String(describing: error.localizedDescription)]) }
    }

    func export(_ format: ExportFormat) {
        guard !busy, !project.visibleMessages.isEmpty else { return }
        let panel = NSSavePanel(); panel.title = L10n.text("导出{0}", [String(describing: format.label)])
        panel.nameFieldStringValue = project.title + (format == .analysisDocx ? "-AI" : "") + "." + format.ext
        panel.allowedContentTypes = [UTType(filenameExtension: format.ext) ?? .data]
        if panel.runModal() == .OK, let url = panel.url {
            performExport(format, to: url)
        }
    }

    func performExport(_ format: ExportFormat, to url: URL, reveal: Bool = true) {
        guard !busy, !project.visibleMessages.isEmpty else { return }
        let snapshot = project, language = L10n.language
        busy = true; progress = L10n.text("正在导出 {0}…", [format.label])
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                L10n.$exportLanguage.withValue(language) {
                    Result {
                        if format == .markdown { try MarkdownExport.write(snapshot, to: url) }
                        else { try DocumentExporter.data(snapshot, format: format).write(to: url, options: .atomic) }
                    }
                }
            }.value
            busy = false; progress = ""
            switch result {
            case .success:
                status = L10n.text("已导出 {0}", [url.lastPathComponent])
                if reveal { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            case .failure(let error): alert = L10n.text("导出失败：{0}", [error.localizedDescription])
            }
        }
    }

    func copyText() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(TextExport.plain(project), forType: .string); status = L10n.text("已复制全部文字") }
}
