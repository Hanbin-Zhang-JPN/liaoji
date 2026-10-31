import SwiftUI
import AppKit
import ChatCore

struct MediaCaptureSheet: View {
    @ObservedObject var model: Workspace
    let shot: Screenshot
    @Environment(\.dismiss) private var dismiss
    @State private var box = Box(x: 0.14, y: 0.3, width: 0.62, height: 0.22)
    @State private var kind = MediaKind.picture
    @State private var speaker = Speaker.other
    @State private var caption = ""
    @State private var keywords = ""
    @State private var excludeCovered = false
    @State private var zoom = 1.0
    @State private var error: String?
    private var covered: Int { model.coveredText(in: shot, box: box).count }
    @Environment(\.locale) private var interfaceLocale
    var body: some View {
        let _ = interfaceLocale.identifier
        VStack(spacing: 0) {
            HStack { Text(L10n.text("框选聊天素材")).font(.system(size: 19, weight: .semibold)); Spacer(); Button(L10n.text("取消")) { dismiss() }.keyboardShortcut(.cancelAction) }.padding(22)
            Divider()
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(L10n.text("在原图上拖出选区")).font(.system(size: 12))
                        Spacer()
                        Button { zoom = max(1, zoom - 0.5) } label: { Image(systemName: "minus.magnifyingglass") }.disabled(zoom <= 1)
                        Button { zoom = min(2, zoom + 0.5) } label: { Image(systemName: "plus.magnifyingglass") }.disabled(zoom >= 2)
                    }
                    ScrollView([.horizontal, .vertical]) {
                        if let image = model.image(for: shot) {
                            CropSelection(image: image, box: $box)
                                .frame(width: 330 * zoom, height: 330 * zoom * Double(shot.height) / Double(shot.width))
                        }
                    }.background(Theme.canvas, in: RoundedRectangle(cornerRadius: 8))
                    DisclosureGroup(L10n.text("精细调整选区")) {
                        VStack(spacing: 6) {
                            cropSlider(L10n.text("左边"), value: Binding(get: { box.x }, set: { box.x = min($0, 1 - box.width) }), range: 0...max(0.001, 1 - box.width))
                            cropSlider(L10n.text("顶部"), value: Binding(get: { box.y }, set: { box.y = min($0, 1 - box.height) }), range: 0...max(0.001, 1 - box.height))
                            cropSlider(L10n.text("宽度"), value: Binding(get: { box.width }, set: { box.width = $0 }), range: 0.02...max(0.02, 1 - box.x))
                            cropSlider(L10n.text("高度"), value: Binding(get: { box.height }, set: { box.height = $0 }), range: 0.01...max(0.01, 1 - box.y))
                        }.padding(.top, 8)
                    }.font(.system(size: 11))
                }.frame(width: 350)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(L10n.text("保存预览")).font(.system(size: 12, weight: .semibold))
                        if let cg = try? MediaImages.crop(shot, box: box, maximum: 700) {
                            Image(nsImage: NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))).resizable().aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: 180).background(Theme.canvas, in: RoundedRectangle(cornerRadius: 7))
                        } else { Text(L10n.text("请框选至少 8 × 8 像素的区域")).font(.system(size: 11)).foregroundStyle(Theme.muted).frame(height: 100) }
                        Picker(L10n.text("素材类型"), selection: $kind) { ForEach(MediaKind.allCases, id: \.self) { Text($0.label).tag($0) } }.pickerStyle(.segmented)
                        Picker(L10n.text("发送者"), selection: $speaker) { Text(model.project.otherName).tag(Speaker.other); Text(model.project.myName).tag(Speaker.me) }
                        TextField(L10n.text("说明（可选）"), text: $caption, axis: .vertical).lineLimit(2...5).textFieldStyle(.roundedBorder)
                        TextField(L10n.text("关键词，例如：旅行、开心"), text: $keywords).textFieldStyle(.roundedBorder)
                        if covered > 0 {
                            Toggle(L10n.text("排除选区内的 {0} 条识别文字", [String(describing: covered)]), isOn: $excludeCovered).font(.system(size: 11))
                            Text(L10n.text("默认保留原文字。若文字来自图片内部，可勾选以避免重复；整个操作可以撤销。")).font(.system(size: 10)).foregroundStyle(Theme.muted)
                        }
                        Text(L10n.text("保存后按原图位置插入对话。截图只能保留静态画面，无法恢复动态表情或原图清晰度。")).font(.system(size: 10)).foregroundStyle(Theme.muted)
                        if let error { Text(error).font(.system(size: 11)).foregroundStyle(.orange) }
                    }
                }.frame(width: 290)
            }.padding(22)
            Divider()
            HStack {
                Text("\(shot.filename)").font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(1)
                Spacer()
                Button(L10n.text("保存到聊天记录")) {
                    if model.addMedia(shot: shot, box: box, kind: kind, speaker: speaker, caption: caption, keywords: keywords, excludeCovered: excludeCovered) { dismiss() }
                    else { error = model.alert; model.alert = nil }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(model.busy || !box.isValid || box.width * Double(shot.width) < 8 || box.height * Double(shot.height) < 8)
            }.padding(20)
        }.frame(width: 710, height: 670).background(Theme.paper).foregroundStyle(Theme.ink).tint(Theme.green)
    }
    private func cropSlider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack { Text(label).frame(width: 28); Slider(value: value, in: range).accessibilityLabel(L10n.text("选区") + label); Text("\(Int(value.wrappedValue * 100))%").monospacedDigit().frame(width: 34) }
    }
}

struct CropSelection: View {
    let image: NSImage
    @Binding var box: Box
    @Environment(\.locale) private var interfaceLocale
    var body: some View {
        let _ = interfaceLocale.identifier
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Image(nsImage: image).resizable().frame(width: geometry.size.width, height: geometry.size.height)
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: geometry.size))
                    path.addRect(CGRect(x: box.x * geometry.size.width, y: box.y * geometry.size.height, width: box.width * geometry.size.width, height: box.height * geometry.size.height))
                }.fill(.black.opacity(0.45), style: FillStyle(eoFill: true)).allowsHitTesting(false)
                Rectangle().strokeBorder(Color.orange, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                    .frame(width: box.width * geometry.size.width, height: box.height * geometry.size.height)
                    .offset(x: box.x * geometry.size.width, y: box.y * geometry.size.height).allowsHitTesting(false)
            }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 2).onChanged { value in
                box = Self.normalized(start: value.startLocation, end: value.location, size: geometry.size)
            }).accessibilityLabel(L10n.text("拖动框选图片区域，也可使用下方精细调整"))
        }
    }
    static func normalized(start: CGPoint, end: CGPoint, size: CGSize) -> Box {
        let ax = min(1, max(0, start.x / max(1, size.width))), ay = min(1, max(0, start.y / max(1, size.height)))
        let bx = min(1, max(0, end.x / max(1, size.width))), by = min(1, max(0, end.y / max(1, size.height)))
        let x = min(0.999, min(ax, bx)), y = min(0.999, min(ay, by))
        return Box(x: x, y: y, width: min(1 - x, max(0.001, abs(ax - bx))), height: min(1 - y, max(0.001, abs(ay - by))))
    }
}
