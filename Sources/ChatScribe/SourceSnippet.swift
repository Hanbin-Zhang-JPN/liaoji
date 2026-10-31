import AppKit
import ChatCore

enum SourceSnippet {
    static func crop(_ image: CGImage, box: Box) -> CGImage? {
        guard box.isValid else { return nil }
        let width = CGFloat(image.width), height = CGFloat(image.height)
        let padding = min(22, max(5, width * 0.012))
        let rect = CGRect(x: CGFloat(box.x) * width, y: CGFloat(box.y) * height, width: CGFloat(box.width) * width, height: CGFloat(box.height) * height)
            .insetBy(dx: -padding, dy: -padding).integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !rect.isEmpty else { return nil }
        return image.cropping(to: rect)
    }
    static func enlarged(_ image: CGImage) -> CGImage {
        let factor = min(2, 2400 / CGFloat(max(image.width, image.height)))
        guard factor > 1 else { return image }
        let width = Int(CGFloat(image.width) * factor), height = Int(CGFloat(image.height) * factor)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }
}
