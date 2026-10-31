import AppKit
import Vision
import ImageIO
import ChatCore

enum OCRService {
    static func validateImages(in project: Project) throws {
        for shot in project.screenshots {
            guard let source = CGImageSourceCreateWithData(shot.imageData as CFData, nil), CGImageSourceGetCount(source) > 0,
                  CGImageSourceGetStatus(source) == .statusComplete,
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue == shot.width,
                  (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue == shot.height else {
                throw OCRFailure(L10n.text("项目中的截图无法完整读取：{0}", [String(describing: shot.filename)]))
            }
        }
    }
    static func prepare(data: Data, filename: String) throws -> Screenshot {
        guard data.count <= 30_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 3600
              ] as CFDictionary) else { throw OCRFailure(L10n.text("无法读取“{0}”。请使用 PNG、JPG、HEIC 或 TIFF 图片（每张不超过 30 MB）。", [String(describing: filename)])) }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let normalized = rep.representation(using: .png, properties: [:]) else { throw OCRFailure(L10n.text("图片转换失败。")) }
        return Screenshot(filename: filename, imageData: normalized, width: image.width, height: image.height)
    }

    static func recognize(_ shot: Screenshot) throws -> Screenshot {
        guard let source = CGImageSourceCreateWithData(shot.imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw OCRFailure(L10n.text("截图已损坏，请重新导入。")) }
        let lines = try recognizeLines(image)
        let bubbles = BubbleDetector.regions(image, top: shot.top, bottom: shot.bottom)
        var output = shot
        output.lines = lines.map { original in
            var line = original
            let box = line.box
            let bubble = bubbles.enumerated().filter { $0.element.box.contains(box.x + box.width / 2, box.y + box.height / 2) }.min { $0.element.box.width * $0.element.box.height < $1.element.box.width * $1.element.box.height }
            line.bubble = bubble?.offset; line.side = bubble?.element.speaker
            return line
        }
        output.recognized = true
        output.error = output.lines.isEmpty ? L10n.text("没有识别到文字。请检查截图清晰度，或手动添加记录。") : nil
        return output
    }

    static func recognizeSnippet(_ shot: Screenshot, box: Box) throws -> String {
        guard let source = CGImageSourceCreateWithData(shot.imageData as CFData, nil), let full = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let snippet = SourceSnippet.crop(full, box: box) else { throw OCRFailure(L10n.text("这条消息没有可读取的原图区域。")) }
        let lines = try recognizeLines(SourceSnippet.enlarged(snippet))
        let text = ChatParser.recognizedText(from: lines).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw OCRFailure(L10n.text("局部未识别出清晰文字，请对照原图手动修正。")) }
        return text
    }

    private static func recognizeLines(_ image: CGImage) throws -> [OCRLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        let supported: [String]
        do { supported = try request.supportedRecognitionLanguages() }
        catch { throw OCRFailure(L10n.text("无法加载本机文字识别语言：{0} {1} · {2}", [String(describing: (error as NSError).domain), String(describing: (error as NSError).code), String(describing: error.localizedDescription)])) }
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR"].filter { supported.contains($0) }
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.004
        do { try VNImageRequestHandler(cgImage: image, options: [:]).perform([request]) }
        catch { throw OCRFailure(L10n.text("本机文字识别失败：{0} {1} · {2}", [String(describing: (error as NSError).domain), String(describing: (error as NSError).code), String(describing: error.localizedDescription)])) }
        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let r = observation.boundingBox
            let box = Box(x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height)
            return OCRLine(candidate.string, box: box, confidence: candidate.confidence)
        }
    }
}

struct OCRFailure: LocalizedError {
    var message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

private enum BubbleDetector {
    struct Region { var box: Box; var speaker: Speaker }
    static func regions(_ image: CGImage, top: Double, bottom: Double) -> [Region] {
        let w = 240, h = min(4096, max(1, Int(Double(image.height) / Double(image.width) * 240)))
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let success = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let c = CGContext(data: bytes.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            c.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h)); return true
        }
        guard success else { return [] }
        // A CG bitmap rendered this way has its first row at the image's top edge.
        var mask = [UInt8](repeating: 0, count: w * h)
        let y0 = max(0, Int(top * Double(h))), y1 = min(h, Int(bottom * Double(h)))
        let bgIndex = min(h - 1, max(0, (y0 + y1) / 2)) * w * 4 + 8 * 4
        let dark = pixels[bgIndex] < 80
        for y in y0..<max(y0, y1) {
            for x in Int(Double(w) * 0.115)..<Int(Double(w) * 0.9) {
                let i = (y * w + x) * 4
                let r = Double(pixels[i]) / 255, g = Double(pixels[i + 1]) / 255, b = Double(pixels[i + 2]) / 255
                if g > 0.42 && g > r * 1.12 && g > b * 1.12 { mask[y * w + x] = 2 }
                else if !dark && r > 0.96 && g > 0.96 && b > 0.96 { mask[y * w + x] = 1 }
                else if dark && r > 0.14 && r < 0.28 && abs(r - g) < 0.035 && abs(g - b) < 0.035 { mask[y * w + x] = 1 }
            }
        }
        var regions: [Region] = []
        for start in mask.indices where mask[start] != 0 {
            let kind = mask[start]
            var queue = [start], cursor = 0
            mask[start] = 0
            var minX = w, maxX = 0, minY = h, maxY = 0
            while cursor < queue.count {
                let index = queue[cursor]; cursor += 1
                let x = index % w, y = index / w
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                for neighbor in [x > 0 ? index - 1 : -1, x < w - 1 ? index + 1 : -1, y > 0 ? index - w : -1, y < h - 1 ? index + w : -1] {
                    if neighbor >= 0 && mask[neighbor] == kind { mask[neighbor] = 0; queue.append(neighbor) }
                }
            }
            let bw = Double(maxX - minX + 1) / Double(w), bh = Double(maxY - minY + 1) / Double(h)
            guard bw > 0.045 && bw < 0.78 && bh > 0.008 && queue.count > 20 else { continue }
            let box = Box(x: Double(minX) / Double(w), y: Double(minY) / Double(h), width: bw, height: bh)
            regions.append(Region(box: box, speaker: kind == 2 ? .me : (box.x + bw / 2 > 0.6 ? .me : .other)))
        }
        return regions
    }
}
