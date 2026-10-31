import SwiftUI
import ChatCore

struct MediaLibraryPane: View {
    @ObservedObject var model: Workspace
    @State private var filter = "all"
    @State private var favoritesOnly = false
    @State private var search = ""
    private var items: [Message] {
        model.project.mediaMessages.filter { m in
            (filter == "all" || m.media?.kind.rawValue == filter) && (!favoritesOnly || m.media?.favorite == true) &&
            (search.isEmpty || (m.text + " " + (m.media?.keywords ?? "") + " " + model.project.name(for: m)).localizedCaseInsensitiveContains(search))
        }
    }
    @Environment(\.locale) private var interfaceLocale
    var body: some View {
        let _ = interfaceLocale.identifier
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker(L10n.text("素材类型"), selection: $filter) {
                    Text(L10n.text("全部")).tag("all"); ForEach(MediaKind.allCases, id: \.self) { Text($0.label).tag($0.rawValue) }
                }.pickerStyle(.segmented).frame(width: 190)
                Toggle(isOn: $favoritesOnly) { Image(systemName: favoritesOnly ? "star.fill" : "star") }.toggleStyle(.button).help(L10n.text("只看收藏"))
                Spacer()
                Button(L10n.text("导出素材…")) { model.exportMedia(items) }.font(.system(size: 11)).disabled(items.isEmpty)
            }.padding(.horizontal, 24).padding(.bottom, 12)
            HStack {
                TextField(L10n.text("搜索说明、关键词或发送者"), text: $search).textFieldStyle(.roundedBorder)
                Text(L10n.text("{0} 项", [String(describing: items.count)])).font(.system(size: 10)).foregroundStyle(Theme.muted)
            }.padding(.horizontal, 24).padding(.bottom, 15)
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        if items.isEmpty {
                            VStack(spacing: 14) {
                                Image(systemName: "photo.stack").font(.system(size: 34, weight: .ultraLight)).foregroundStyle(Theme.green)
                                Text(model.project.mediaMessages.isEmpty ? L10n.text("把图片和表情也留下来") : L10n.text("没有符合筛选的素材")).font(.system(size: 17))
                                Text(model.project.mediaMessages.isEmpty ? L10n.text("选择左侧截图，点击“框选素材”，保存后会按原图位置插入聊天。") : L10n.text("试试其他分类、关键词，或关闭只看收藏。")).font(.system(size: 11)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                                if model.project.mediaMessages.isEmpty { Button(L10n.text("框选当前截图")) { model.beginMediaCapture() }.disabled(model.currentShot == nil) }
                            }.frame(maxWidth: .infinity).padding(.vertical, 65)
                        }
                        ForEach(items) { m in MediaLibraryCard(model: model, message: m).id(m.id) }
                    }.padding(.horizontal, 24).padding(.bottom, 24)
                }.onChange(of: model.selectedMessage) { _, id in if let id { withAnimation { reader.scrollTo(id, anchor: .center) } } }
                .onAppear { if let id = model.selectedMessage { reader.scrollTo(id, anchor: .center) } }
            }
        }.disabled(model.busy)
    }
}

private struct MediaLibraryCard: View {
    @ObservedObject var model: Workspace
    let message: Message
    @Environment(\.locale) private var interfaceLocale
    var body: some View {
        let _ = interfaceLocale.identifier
        let m = model.project.messages.first { $0.id == message.id } ?? message
        let similar = model.similarMedia(to: m)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker(L10n.text("分类"), selection: Binding(get: { m.media?.kind ?? .picture }, set: { value in model.edit(m.id) { $0.media?.kind = value } })) {
                    ForEach(MediaKind.allCases, id: \.self) { Text($0.label).tag($0) }
                }.labelsHidden().frame(width: 90)
                Menu {
                    Button(model.project.otherName) { model.edit(m.id) { $0.speaker = .other } }
                    Button(model.project.myName) { model.edit(m.id) { $0.speaker = .me } }
                } label: { Text(model.project.name(for: m)).font(.system(size: 11)) }.menuStyle(.borderlessButton).fixedSize()
                Spacer()
                Button { model.edit(m.id) { $0.media?.favorite.toggle() } } label: { Image(systemName: m.media?.favorite == true ? "star.fill" : "star") }.buttonStyle(.plain).foregroundStyle(Theme.green).help(m.media?.favorite == true ? L10n.text("取消收藏") : L10n.text("收藏素材"))
                Menu {
                    Button(L10n.text("在聊天中查看")) { model.showMediaSource(m) }
                    Button(L10n.text("核对这个素材")) { model.startProofreading(from: m.id) }
                    Button(L10n.text("导出这份素材…")) { model.exportMedia([m]) }
                    Divider(); Button(L10n.text("从文档排除")) { model.edit(m.id) { $0.excluded = true } }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
            }
            if let image = model.mediaImage(for: m) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(maxWidth: .infinity, maxHeight: 210)
                    .background(Theme.paper, in: RoundedRectangle(cornerRadius: 7)).onTapGesture { model.select(m) }.accessibilityLabel(L10n.text("保存的") + (m.media?.kind.label ?? L10n.text("图片")))
            }
            TextField(L10n.text("素材说明（可选）"), text: Binding(get: { m.text }, set: { value in model.edit(m.id, coalescing: "text") { $0.text = value } }), axis: .vertical).textFieldStyle(.plain).lineLimit(1...8)
            TextField(L10n.text("关键词，例如：旅行、开心"), text: Binding(get: { m.media?.keywords ?? "" }, set: { value in model.edit(m.id, coalescing: "keywords") { $0.media?.keywords = value } })).font(.system(size: 11)).textFieldStyle(.roundedBorder)
            HStack {
                if let index = model.project.screenshots.firstIndex(where: { $0.id == m.sourceID }) { Text(L10n.text("来自截图 {0}", [String(describing: index + 1)])).font(.system(size: 10)).foregroundStyle(Theme.muted) }
                Spacer()
                Button(L10n.text("回到原图与上下文")) { model.showMediaSource(m) }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.green)
            }
            if !similar.isEmpty {
                DisclosureGroup(L10n.text("{0} 份可能重复的素材（保留各次发送记录）", [String(describing: similar.count)])) {
                    ForEach(similar) { other in
                        Button(L10n.text("查看：{0} · {1}", [String(describing: model.project.name(for: other)), String(describing: other.text.isEmpty ? (other.media?.kind.label ?? L10n.text("素材")) : other.text)])) { model.showMediaSource(other) }.buttonStyle(.plain).font(.system(size: 11)).padding(.top, 6)
                    }
                }.font(.system(size: 10)).foregroundStyle(Theme.muted)
            }
        }.padding(15).background(Theme.card, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(model.selectedMessage == m.id ? Theme.green.opacity(0.5) : .clear))
    }
}
