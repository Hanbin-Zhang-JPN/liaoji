import AppKit
import ImageIO
import CryptoKit
import ChatCore

enum MediaImages {
    static func crop(_ shot: Screenshot, box: Box, maximum: Int = 1600) throws -> CGImage {
        guard box.isValid, let source = CGImageSourceCreateWithData(shot.imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw OCRFailure(L10n.text("素材的原截图无法读取。")) }
        let rect = CGRect(x: box.x * Double(image.width), y: box.y * Double(image.height), width: box.width * Double(image.width), height: box.height * Double(image.height))
            .integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard rect.width >= 8, rect.height >= 8, let cropped = image.cropping(to: rect) else { throw OCRFailure(L10n.text("选区太小，请重新框选图片或表情。")) }
        let scale = min(1, CGFloat(maximum) / CGFloat(max(cropped.width, cropped.height)))
        guard scale < 1 else { return cropped }
        let w = max(1, Int(CGFloat(cropped.width) * scale)), h = max(1, Int(CGFloat(cropped.height) * scale))
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw OCRFailure(L10n.text("素材图片处理失败。")) }
        context.interpolationQuality = .high; context.draw(cropped, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let result = context.makeImage() else { throw OCRFailure(L10n.text("素材图片处理失败。")) }; return result
    }
    static func crop(_ message: Message, in project: Project, maximum: Int = 1600) throws -> CGImage {
        guard message.media != nil, let box = message.box, let shot = project.screenshots.first(where: { $0.id == message.sourceID }) else { throw OCRFailure(L10n.text("找不到素材对应的截图区域。")) }
        return try crop(shot, box: box, maximum: maximum)
    }
    static func png(_ image: CGImage) throws -> Data {
        try autoreleasepool {
            guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw OCRFailure(L10n.text("素材图片编码失败。")) }; return data
        }
    }
    static func fingerprint(_ image: CGImage) -> String? {
        // Only exact normalized thumbnails are hints; never remove a repeated sending record.
        let w = 24, h = 24
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let bytes = context.data else { return nil }
        context.interpolationQuality = .high; context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var data = Data(bytes: bytes, count: w * h * 4)
        data.append(Data(String(Int((Double(image.width) / Double(image.height) * 100).rounded())).utf8))
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    static func export(_ messages: [Message], in project: Project, to parent: URL) throws -> URL {
        let folder = parent.appendingPathComponent(L10n.text("聊迹素材-") + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        do {
            var index = L10n.text("# {0} · 素材\n\n图片为聊天截图中的静态裁切。\n\n", [String(describing: project.title)])
            var total = 0
            for (offset, message) in messages.enumerated() where message.media != nil && !message.excluded {
                let data = try png(crop(message, in: project, maximum: 3600))
                total += data.count
                guard total <= 300_000_000 else { throw OCRFailure(L10n.text("素材导出超过 300 MB，请缩小筛选范围分批导出。")) }
                let filename = String(format: "%04d", offset + 1) + "_" + (message.media?.kind.label ?? L10n.text("图片")) + ".png"
                try data.write(to: folder.appendingPathComponent(filename), options: .atomic)
                let source = project.screenshots.first { $0.id == message.sourceID }?.filename ?? ""
                index += L10n.text("## {0} · {1}\n\n![]({2})\n\n{3}\n\n来源：{4}\n\n", [String(describing: offset + 1), String(describing: project.name(for: message)), String(describing: filename), String(describing: message.documentText), String(describing: source)])
            }
            try Data(index.utf8).write(to: folder.appendingPathComponent(L10n.text("素材目录.md")), options: .atomic)
            return folder
        } catch { try? FileManager.default.removeItem(at: folder); throw error }
    }
}
