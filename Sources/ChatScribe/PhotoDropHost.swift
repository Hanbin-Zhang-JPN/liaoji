import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ChatCore

enum ScreenshotDrag {
    static let type = "com.liaoji.screenshot-order"
    static func provider(for id: UUID) -> NSItemProvider {
        let item = NSItemProvider()
        item.registerDataRepresentation(forTypeIdentifier: type, visibility: .ownProcess) { completion in completion(Data(id.uuidString.utf8), nil); return nil }
        return item
    }
}

enum ImageInput: Sendable {
    case file(URL)
    case bytes(Data, String)

    func prepare() throws -> Screenshot {
        switch self {
        case .file(let url):
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 30_000_000 else { throw OCRFailure(L10n.text("{0}：图片超过 30 MB。", [String(describing: url.lastPathComponent)])) }
            return try OCRService.prepare(data: Data(contentsOf: url), filename: url.lastPathComponent)
        case .bytes(let data, let name): return try OCRService.prepare(data: data, filename: name)
        }
    }
}

struct PhotoDropHost: NSViewRepresentable {
    @ObservedObject var model: Workspace
    func makeNSView(context: Context) -> PhotoHostingView { PhotoHostingView(model: model) }
    func updateNSView(_ view: PhotoHostingView, context: Context) { view.rootView = ContentView(model: model) }
}

final class PhotoHostingView: NSHostingView<ContentView> {
    private weak var model: Workspace?
    init(model: Workspace) {
        self.model = model
        super.init(rootView: ContentView(model: model))
        registerForDraggedTypes(NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) } + [.fileURL, .png, .tiff, NSPasteboard.PasteboardType(UTType.jpeg.identifier), NSPasteboard.PasteboardType(UTType.heic.identifier)])
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    @available(*, unavailable) required init(rootView: ContentView) { fatalError() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard model?.busy == false else { return [] }
        guard PhotoDropReader.canRead(sender.draggingPasteboard) else { return super.draggingEntered(sender) }
        model?.dropTargeted = true
        return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard model?.busy == false else { return [] }
        return PhotoDropReader.canRead(sender.draggingPasteboard) ? .copy : super.draggingUpdated(sender)
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { model?.dropTargeted = false; super.draggingExited(sender) }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard model?.busy == false else { return false }
        return PhotoDropReader.canRead(sender.draggingPasteboard) ? true : super.prepareForDragOperation(sender)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        model?.dropTargeted = false
        guard let model, !model.busy else { return false }
        guard PhotoDropReader.canRead(sender.draggingPasteboard) else { return super.performDragOperation(sender) }
        guard let id = model.beginReceiving() else { return false }
        let accepted = PhotoDropReader.receive(sender.draggingPasteboard, cancellation: { [weak model] cancel in model?.setReceiveCancellation(cancel, id: id) }, completion: { [weak model] inputs, errors in model?.completeReceiving(inputs, errors: errors, id: id) })
        if !accepted { model.rejectReceiving(id: id) }
        return accepted
    }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) { model?.dropTargeted = false; super.concludeDragOperation(sender) }
}

enum PhotoDropReader {
    static func canRead(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.canReadObject(forClasses: [NSFilePromiseReceiver.self, NSURL.self, NSImage.self], options: [.urlReadingFileURLsOnly: true])
    }

    // Photos supplies file promises, Finder supplies URLs, and some apps supply image bytes.
    // Prefer promises to avoid importing both the original image and its preview.
    @MainActor @discardableResult static func receive(_ pasteboard: NSPasteboard, cancellation: (@escaping () -> Void) -> Void = { _ in }, completion: @escaping @MainActor ([ImageInput], [String]) -> Void) -> Bool {
        if let promises = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver], !promises.isEmpty {
            let cancel = receivePromises(promises, completion: completion)
            cancellation(cancel)
            return true
        }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            let sorted = urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            completion(sorted.map { .file($0) }, [])
            return true
        }
        var images: [ImageInput] = []
        for (index, item) in (pasteboard.pasteboardItems ?? []).enumerated() {
            let representation = item.types.lazy.filter { UTType($0.rawValue)?.conforms(to: .image) == true }.compactMap { type in item.data(forType: type).map { (type, $0) } }.first
            if let (type, data) = representation {
                images.append(.bytes(data, L10n.text("相册图片-{0}.", [String(describing: index + 1)]) + (UTType(type.rawValue)?.preferredFilenameExtension ?? "png")))
            }
        }
        if images.isEmpty, let image = NSImage(pasteboard: pasteboard), let data = image.tiffRepresentation { images.append(.bytes(data, L10n.text("相册图片.tiff"))) }
        guard !images.isEmpty else { return false }
        completion(images, [])
        return true
    }

    @MainActor @discardableResult static func receivePromises(_ promises: [NSFilePromiseReceiver], completion: @escaping @MainActor ([ImageInput], [String]) -> Void) -> () -> Void {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("Liaoji-Drop-" + UUID().uuidString, isDirectory: true)
        do { try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true) }
        catch { completion([], [L10n.text("无法接收图片：{0}", [String(describing: error.localizedDescription)])]); return {} }
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1; queue.name = "com.liaoji.photos-import"
        let batch = PromiseBatch(destination: destination, promises: promises, queue: queue, completion: completion)
        var expected = 0
        for (index, promise) in promises.enumerated() {
            promise.receivePromisedFiles(atDestination: destination, options: [:], operationQueue: queue) { url, error in
                if batch.isCancelled { batch.add(index: index, input: nil, error: nil); return }
                do {
                    if let error { throw error }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= 30_000_000 else { throw OCRFailure(L10n.text("{0}：图片超过 30 MB。", [String(describing: url.lastPathComponent)])) }
                    // Read inside the promise callback while AppKit's read coordination is active.
                    batch.add(index: index, input: .bytes(try Data(contentsOf: url), url.lastPathComponent), error: nil)
                } catch { batch.add(index: index, input: nil, error: L10n.text("接收图片失败：{0}", [String(describing: error.localizedDescription)])) }
            }
            expected += max(1, promise.fileNames.count)
        }
        batch.seal(expected: expected)
        return { batch.cancel() }
    }
}

private final class PromiseBatch: @unchecked Sendable {
    let destination: URL
    let promises: [NSFilePromiseReceiver]
    let queue: OperationQueue
    let completion: @MainActor ([ImageInput], [String]) -> Void
    private let lock = NSLock()
    private var results: [(Int, ImageInput?)] = []
    private var errors: [String] = []
    private var expected: Int?
    private var finished = false
    private var totalBytes = 0
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    init(destination: URL, promises: [NSFilePromiseReceiver], queue: OperationQueue, completion: @escaping @MainActor ([ImageInput], [String]) -> Void) {
        self.destination = destination; self.promises = promises; self.queue = queue; self.completion = completion
    }
    func add(index: Int, input: ImageInput?, error: String?) {
        lock.lock()
        if let error { errors.append(error) }
        var kept = input
        if case .bytes(let data, _) = input {
            totalBytes += data.count
            if totalBytes > 300_000_000 { kept = nil; errors.append(L10n.text("这批图片超过 300 MB，请分批导入。")) }
        }
        results.append((index, kept))
        finishIfReady()
        lock.unlock()
    }
    func seal(expected: Int) { lock.lock(); self.expected = expected; finishIfReady(); lock.unlock() }
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        guard !finished else { return }
        cancelled = true; finished = true; results = results.map { ($0.0, nil) }
        DispatchQueue.main.async { [self] in completion([], []) }
        if let expected, results.count >= expected { try? FileManager.default.removeItem(at: destination) }
    }
    private func finishIfReady() {
        if cancelled {
            if let expected, results.count >= expected { try? FileManager.default.removeItem(at: destination) }
            return
        }
        guard !finished, let expected, results.count >= expected else { return }
        finished = true
        let images = results.enumerated().sorted { $0.element.0 == $1.element.0 ? $0.offset < $1.offset : $0.element.0 < $1.element.0 }.compactMap { $0.element.1 }
        let errors = errors
        DispatchQueue.main.async { [self] in
            completion(images, errors)
            try? FileManager.default.removeItem(at: destination)
        }
    }
}
