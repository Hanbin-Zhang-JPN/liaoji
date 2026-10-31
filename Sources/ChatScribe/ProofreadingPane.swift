import SwiftUI
import AppKit
import ChatCore

struct ProofreadingPane: View {
    @ObservedObject var model: Workspace
    @Environment(\.locale) private var interfaceLocale
    var body: some View {
        let _ = interfaceLocale.identifier
        VStack(spacing: 0) {
            HStack {
                Text(L10n.text("已核对 {0} / {1}", [String(describing: model.proofreadingDone), String(describing: model.proofreadingTotal)])).font(.system(size: 11)).foregroundStyle(Theme.muted)
                Spacer()
                Picker(L10n.text("核对范围"), selection: Binding(get: { model.proofreadingScope }, set: { model.setProofreadingScope($0) })) {
                    ForEach(ProofreadingScope.allCases, id: \.self) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().frame(width: 185)
            }.padding(.horizontal, 24).padding(.bottom, 14)
            if let message = model.proofMessage {
                ScrollView {
                    ProofreadingDetails(model: model, message: message).id(message.id).padding(.horizontal, 24).padding(.bottom, 20)
                }
                Divider()
                HStack(spacing: 10) {
                    Button { model.navigateProofreading(by: -1) } label: { Image(systemName: "chevron.left") }.help(L10n.text("上一条（⌘[）")).disabled(!model.canNavigateProofreading(by: -1))
                    Button { model.navigateProofreading(by: 1) } label: { Image(systemName: "chevron.right") }.help(L10n.text("下一条，保留待核对（⌘]）")).disabled(!model.canNavigateProofreading(by: 1))
                    Menu {
                        Button(L10n.text("从文档排除此条")) { model.excludeProofMessage() }
                        Button(L10n.text("退出快速核对")) { model.endProofreading() }
                    } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                    Spacer()
                    Button(L10n.text("已核对，下一条 ⌘↩")) { model.confirmProofreading() }.buttonStyle(.borderedProminent)
                        .disabled(message.media == nil && message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding(.horizontal, 24).padding(.vertical, 14)
            } else {
                VStack(spacing: 15) {
                    Image(systemName: "checkmark.circle").font(.system(size: 35, weight: .light)).foregroundStyle(Theme.green)
                    Text(model.proofreadingTotal == 0 ? L10n.text("没有需要核对的消息") : (model.proofreadingPending == 0 ? L10n.text("全部消息已核对") : L10n.text("这一组已核对完成"))).font(.system(size: 20, weight: .medium))
                    if model.proofreadingPending > 0 {
                        Text(L10n.text("还有 {0} 条普通消息待核对", [String(describing: model.proofreadingPending)])).font(.system(size: 12)).foregroundStyle(Theme.muted)
                        Button(L10n.text("继续核对全部")) { model.setProofreadingScope(.pending) }.buttonStyle(.borderedProminent)
                    } else {
                        Text(model.proofreadingTotal == 0 ? L10n.text("已排除的消息不计入核对。") : L10n.text("核对进度已随项目保存在本机")).font(.system(size: 12)).foregroundStyle(Theme.muted)
                        Button(L10n.text("返回整理")) { model.endProofreading() }.buttonStyle(.borderedProminent)
                        if model.proofreadingTotal > 0 { Button(L10n.text("重新核对一遍")) { model.resetProofreadingProgress() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.muted) }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(30)
            }
        }.disabled(model.busy)
    }
}

private struct ProofreadingDetails: View {
    @ObservedObject var model: Workspace
    let message: Message
    @Environment(\.locale) private var interfaceLocale
    var body: some View {
        let _ = interfaceLocale.identifier
        let m = model.project.messages.first { $0.id == message.id } ?? message
        let reasons = Proofreading.reasons(for: m)
        VStack(alignment: .leading, spacing: 16) {
            if !reasons.isEmpty {
                Label(reasons.joined(separator: " · "), systemImage: "info.circle").font(.system(size: 11)).foregroundStyle(Theme.green)
            }
            if let image = m.media != nil ? model.mediaImage(for: m) : model.proofImage(for: m) {
                ProofreadingCrop(image: image)
            } else {
                Label(L10n.text("这条没有原图定位区域，请手工核对文字。"), systemImage: "text.bubble").font(.system(size: 12)).foregroundStyle(Theme.muted).padding(.vertical, 20)
            }
            HStack {
                Text(m.media == nil ? L10n.text("当前文字") : L10n.text("{0}说明（可选）", [String(describing: m.media!.kind.label)])).font(.system(size: 12, weight: .semibold))
                Spacer()
                Menu {
                    ForEach(Speaker.allCases.filter { m.media == nil || $0 != .system }, id: \.self) { speaker in Button(speaker.label) { model.edit(m.id) { $0.speaker = speaker } } }
                } label: { Text(model.project.name(for: m)).font(.system(size: 11)) }.menuStyle(.borderlessButton).fixedSize()
            }
            TextField(L10n.text("对照上方原图，直接修改这里的文字…"), text: Binding(get: { model.project.messages.first { $0.id == m.id }?.text ?? m.text }, set: { value in model.edit(m.id, coalescing: "text") { $0.text = value } }), axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 16)).lineSpacing(7).lineLimit(2...40)
                .padding(16).frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.green.opacity(0.35)))
                .accessibilityLabel(L10n.text("核对中的消息文字"))
            HStack {
                if let original = m.originalText, original != m.text { Text(L10n.text("已修改 · 确认后才标记已核对")).font(.system(size: 10)).foregroundStyle(Theme.muted) }
                Spacer()
                if m.media == nil && m.box != nil && m.sourceID != nil {
                    Button(model.snippetBusy ? L10n.text("局部识别处理中…") : L10n.text("局部重新识别")) { model.requestSnippetRecognition() }.font(.system(size: 11)).disabled(model.snippetBusy)
                }
            }
            if let error = model.snippetError { Text(L10n.display(error)).font(.system(size: 11)).foregroundStyle(Theme.muted).textSelection(.enabled) }
            if let candidate = model.snippetCandidate {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.text("局部识别结果（尚未替换）")).font(.system(size: 11, weight: .medium))
                    Text(candidate).font(.system(size: 14)).lineSpacing(5).textSelection(.enabled)
                    HStack {
                        Button(candidate == m.text ? L10n.text("保留当前文字") : L10n.text("采用此结果")) { model.applySnippetCandidate() }.controlSize(.small)
                        Button(L10n.text("不用此结果")) { model.invalidateSnippet() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.muted)
                    }
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Theme.pale, in: RoundedRectangle(cornerRadius: 9))
            }
            if let original = Proofreading.originalText(for: m, in: model.project) {
                DisclosureGroup(m.originalText != nil ? L10n.text("查看初次识别文字") : L10n.text("查看原图区域的原识别文字")) {
                    Text(original).font(.system(size: 12)).lineSpacing(4).textSelection(.enabled).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 9)
                }.font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            DisclosureGroup(L10n.text("单条署名（群聊可用）")) {
                TextField(L10n.text("留空时使用默认称呼"), text: Binding(get: { model.project.messages.first { $0.id == m.id }?.customName ?? "" }, set: { value in model.edit(m.id, coalescing: "name") { $0.customName = value } })).textFieldStyle(.roundedBorder).padding(.top, 8)
            }.font(.system(size: 11)).foregroundStyle(Theme.muted)
            Text(L10n.text("提示只帮助定位疑点，请以原图为准。")).font(.system(size: 10)).foregroundStyle(Theme.muted)
        }
    }
}

private struct ProofreadingCrop: View {
    let image: NSImage
    @AppStorage("proofreadingZoom") private var zoom = 1.0
    @State private var availableWidth: CGFloat = 420
    private var scale: CGFloat { CGFloat(min(3, max(1, zoom))) }
    @Environment(\.locale) private var interfaceLocale
    var body: some View {
        let _ = interfaceLocale.identifier
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(L10n.text("原图文字")).font(.system(size: 12, weight: .semibold))
                Spacer()
                Button { zoom = max(1, zoom - 0.5) } label: { Image(systemName: "minus.magnifyingglass") }.buttonStyle(.plain).disabled(scale <= 1).help(L10n.text("缩小原文"))
                Text("\(Int(scale * 100))%").font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.muted)
                Button { zoom = min(3, zoom + 0.5) } label: { Image(systemName: "plus.magnifyingglass") }.buttonStyle(.plain).disabled(scale >= 3).help(L10n.text("放大原文"))
            }
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                        .frame(width: min(max(1, geometry.size.width), max(90, image.size.width * 0.8)) * scale).accessibilityLabel(L10n.text("当前消息的原图局部"))
                }
                .onAppear { availableWidth = max(1, geometry.size.width) }
                .onChange(of: geometry.size.width) { _, width in availableWidth = max(1, width) }
            }.frame(height: max(85, min(220, image.size.height / max(1, image.size.width) * min(availableWidth, max(90, image.size.width * 0.8)))))
                .background(Theme.paper, in: RoundedRectangle(cornerRadius: 8)).clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
