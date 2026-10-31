import AppKit
import ChatCore
import UniformTypeIdentifiers

enum ImportChecks {
    @MainActor static func run(folder: URL) async throws {
        let a = Demo.screenshot(index: 0), b = Demo.screenshot(index: 1)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        var output: [ImageInput] = [], errors: [String] = [], finished = false
        func receive() throws {
            output = []; errors = []; finished = false
            guard PhotoDropReader.receive(board, completion: { inputs, failures in output = inputs; errors = failures; finished = true }) else { throw OCRFailure("拖入图片未被接受") }
        }
        func verify(_ condition: Bool, _ label: String) throws { if !condition { throw OCRFailure("图片导入检查失败：" + label) } }
        board.writeObjects([NSPasteboardItem()])
        try verify(!PhotoDropReader.canRead(board), "空拖拽应被拒绝")
        let raw = NSPasteboardItem(); raw.setData(a, forType: .png)
        board.clearContents(); board.writeObjects([raw])
        try verify(PhotoDropReader.canRead(board), "接收图片字节")
        try receive()
        try verify(finished && errors.isEmpty && output.count == 1, "PNG 拖入")
        let prepared = try output[0].prepare()
        try verify(prepared.width > 0 && prepared.height > 0, "图片规范化")
        let tiff = NSImage(data: b)!.tiffRepresentation!
        let rawAgain = NSPasteboardItem(); rawAgain.setData(a, forType: .png)
        let raw2 = NSPasteboardItem(); raw2.setData(tiff, forType: .tiff)
        board.clearContents(); board.writeObjects([rawAgain, raw2])
        try receive()
        try verify(finished && errors.isEmpty && output.count == 2, "多个图片字节表示")
        let firstURL = folder.appendingPathComponent("IMG_2.png"), secondURL = folder.appendingPathComponent("IMG_10.png")
        try a.write(to: firstURL); try b.write(to: secondURL)
        board.clearContents(); board.writeObjects([secondURL as NSURL, firstURL as NSURL])
        try receive()
        try verify(output.count == 2 && (try output[0].prepare()).filename == "IMG_2.png", "访达文件自然排序")

        // The controlled receivers exercise AppKit's Photos-style promise callback contract,
        // including delayed delivery, multiple files per receiver and failed exports.
        let slow = CheckPromise(files: [("first.png", a)], delay: 0.06)
        let fast = CheckPromise(files: [("second.png", b)], delay: 0)
        let multi = CheckPromise(files: [("third.png", a), ("fourth.png", b)], delay: 0.01)
        let failed = CheckPromise(files: [], delay: 0.01, fails: true)
        output = []; errors = []; finished = false
        PhotoDropReader.receivePromises([slow, fast, multi, failed]) { inputs, failures in output = inputs; errors = failures; finished = true }
        let deadline = Date().addingTimeInterval(5)
        while !finished && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        try verify(finished, "异步接收必须完成")
        try verify(output.count == 4 && errors.count == 1, "部分失败不丢弃已成功的图片")
        let names = try output.map { try $0.prepare().filename }
        try verify(names == ["first.png", "second.png", "third.png", "fourth.png"], "完成先后不改变拖入顺序")
        if let destination = slow.destination { try verify(!FileManager.default.fileExists(atPath: destination.path), "清理临时接收文件") }
        let cancelled = CheckPromise(files: [("cancelled.png", a)], delay: 0.06)
        finished = false; var completions = 0
        let cancel = PhotoDropReader.receivePromises([cancelled]) { inputs, failures in
            output = inputs; errors = failures; finished = true; completions += 1
        }
        cancel()
        while !finished && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        try verify(finished && output.isEmpty && errors.isEmpty, "取消接收立即完成")
        let cleanupDeadline = Date().addingTimeInterval(2)
        while let location = cancelled.destination, FileManager.default.fileExists(atPath: location.path), Date() < cleanupDeadline { try await Task.sleep(nanoseconds: 10_000_000) }
        try verify(completions == 1, "取消后迟到回调不重复完成")
        if let location = cancelled.destination { try verify(!FileManager.default.fileExists(atPath: location.path), "取消后的临时文件清理") }
        print("PASS: PNG/TIFF pasteboard images, multiple images, Finder URL order, delayed Photos-style file promises, legacy multi-file promises, partial failures and temporary-file cleanup")
    }
}

private final class CheckPromise: NSFilePromiseReceiver {
    let files: [(String, Data)]
    let delay: Double, fails: Bool
    var called = false
    var destination: URL?
    init(files: [(String, Data)], delay: Double, fails: Bool = false) { self.files = files; self.delay = delay; self.fails = fails; super.init() }
    required init?(pasteboardPropertyList propertyList: Any, ofType type: NSPasteboard.PasteboardType) { return nil }
    override var fileNames: [String] { called ? files.map(\.0) : [] }
    override func receivePromisedFiles(atDestination destination: URL, options: [AnyHashable: Any] = [:], operationQueue: OperationQueue, reader: @escaping (URL, Error?) -> Void) {
        self.destination = destination; called = true
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [self] in
            operationQueue.addOperation {
                if self.fails { reader(destination, OCRFailure("模拟照片导出失败")); return }
                for (name, data) in self.files {
                    let url = destination.appendingPathComponent(name)
                    do { try data.write(to: url); reader(url, nil) } catch { reader(url, error) }
                }
            }
        }
    }
}
