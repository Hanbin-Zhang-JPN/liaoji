import AppKit
import ChatCore

enum Demo {
    static func screenshot(index: Int) -> Data {
        let size = NSSize(width: 750, height: 1624)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(calibratedWhite: 0.93, alpha: 1).setFill(); NSRect(origin: .zero, size: size).fill()
        func text(_ s: String, x: CGFloat, y: CGFloat, width: CGFloat, size fontSize: CGFloat, color: NSColor = .black, bold: Bool = false) {
            let style = NSMutableParagraphStyle(); style.lineSpacing = 8
            (s as NSString).draw(in: NSRect(x: x, y: 1624 - y - 110, width: width, height: 110), withAttributes: [.font: bold ? NSFont.boldSystemFont(ofSize: fontSize) : NSFont.systemFont(ofSize: fontSize), .foregroundColor: color, .paragraphStyle: style])
        }
        text("9:41", x: 43, y: 26, width: 150, size: 25, bold: true)
        text("‹", x: 35, y: 90, width: 60, size: 47)
        text("小林", x: 324, y: 105, width: 160, size: 32, bold: true)
        text("···", x: 660, y: 94, width: 60, size: 38)
        text(index == 0 ? "星期五 10:30" : "星期五 10:35", x: 268, y: 225, width: 280, size: 23, color: .gray)
        let conversations: [[(Bool, String, CGFloat)]] = [
            [(false, "周末一起去散步吧？", 120), (true, "好呀，想去哪里？", 120),
             (false, "去公园吧，那里有咖啡店。", 160), (true, "那我们周六下午两点见。\n记得带上相机。", 190)],
            [(false, "去公园吧，那里有咖啡店。", 160), (true, "那我们周六下午两点见。\n记得带上相机。", 190),
             (false, "没问题！我来查一下路线。", 150), (true, "好的，到时候见！", 120)]
        ]
        var y: CGFloat = 320
        for (mine, content, height) in conversations[index] {
            let avatarX: CGFloat = mine ? 659 : 25, bubbleX: CGFloat = mine ? 185 : 108, bubbleW: CGFloat = mine ? 450 : 510
            NSColor(calibratedRed: mine ? 0.38 : 0.68, green: mine ? 0.53 : 0.61, blue: mine ? 0.45 : 0.48, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: avatarX, y: 1624 - y - 66, width: 66, height: 66), xRadius: 8, yRadius: 8).fill()
            text(mine ? "我" : "林", x: avatarX + 16, y: y + 12, width: 55, size: 30, color: .white)
            (mine ? NSColor(calibratedRed: 0.59, green: 0.91, blue: 0.42, alpha: 1) : NSColor.white).setFill()
            NSBezierPath(roundedRect: NSRect(x: bubbleX, y: 1624 - y - height, width: bubbleW, height: height), xRadius: 13, yRadius: 13).fill()
            text(content, x: bubbleX + 25, y: y + 27, width: bubbleW - 50, size: 31)
            y += height + 72
        }
        NSColor(calibratedWhite: 0.97, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: 750, height: 143).fill()
        text("＋", x: 675, y: 1500, width: 60, size: 42)
        NSColor.white.setFill(); NSBezierPath(roundedRect: NSRect(x: 95, y: 57, width: 510, height: 63), xRadius: 8, yRadius: 8).fill()
        NSColor.black.setFill(); NSBezierPath(roundedRect: NSRect(x: 252, y: 17, width: 246, height: 9), xRadius: 5, yRadius: 5).fill()
        image.unlockFocus()
        return NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    }
}
