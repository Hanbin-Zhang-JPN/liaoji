import SwiftUI
import AppKit
import ChatCore

struct ContentView: View {
    @ObservedObject var model: Workspace
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.simplifiedChinese.rawValue
    @State private var settings = false
    @State private var searchVisible = false
    @State private var deleteShot: UUID?
    @State private var dropShot: UUID?
    @FocusState private var searchFocused: Bool
    private var empty: Bool { model.project.screenshots.isEmpty && model.project.messages.isEmpty && !model.busy }
    private var appearance: AppearanceMode { AppearanceMode(rawValue: appearanceMode) ?? .system }
    @Environment(\.locale) private var interfaceLocale
    var body: some View {
        let _ = interfaceLocale.identifier
        VStack(spacing: 0) {
            header
            Divider()
            if empty { welcome }
            else {
                HStack(spacing: 0) {
                    sourcePanel.frame(width: 310)
                    Divider()
                    VStack(spacing: 0) {
                        editorHeader
                        if model.preview { documentPreview } else if model.proofreading { ProofreadingPane(model: model) } else if model.mediaLibrary { MediaLibraryPane(model: model) } else { transcript }
                    }.frame(minWidth: 430, maxWidth: .infinity)
                }
            }
            footer
        }.background(Theme.canvas).foregroundStyle(Theme.ink).font(.system(size: 13)).tint(Theme.green).preferredColorScheme(appearance.scheme).environment(\.locale, Locale(identifier: appLanguage))
        .onAppear { appearance.apply() }
        .onChange(of: appearanceMode) { _, _ in appearance.apply() }
        .overlay {
            if model.dropTargeted {
                ZStack {
                    Theme.green.opacity(0.12)
                    RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.green, style: StrokeStyle(lineWidth: 2, dash: [8])).padding(10)
                    Label(L10n.text("松开以导入图片"), systemImage: "photo.badge.plus").font(.title3.weight(.medium)).padding(25).background(Theme.paper, in: RoundedRectangle(cornerRadius: 14))
                }.allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $settings) { OptionsSheet(model: model) }
        .sheet(item: $model.captureShot) { shot in MediaCaptureSheet(model: model, shot: shot) }
        .alert(L10n.text("聊迹"), isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })) {
            Button(L10n.text("知道了")) { model.alert = nil }
        } message: { Text(L10n.display(model.alert ?? "")) }
        .alert(L10n.text("移除这张截图？"), isPresented: Binding(get: { deleteShot != nil }, set: { if !$0 { deleteShot = nil } })) {
            Button(L10n.text("取消"), role: .cancel) { deleteShot = nil }
            Button(L10n.text("移除"), role: .destructive) { if let id = deleteShot { model.removeShot(id) }; deleteShot = nil }
        } message: { Text(L10n.text("将同时移除对应文字和素材，可以撤销。原始图片仍保留在原处。")) }
    }
    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "text.bubble.fill").font(.system(size: 21)).foregroundStyle(Theme.green)
            Text(L10n.text("聊迹")).font(.system(size: 21, weight: .semibold, design: .serif))
            Spacer()
            if model.undoLabel != nil {
                Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }.buttonStyle(.plain).help(L10n.text("撤销上一步（⌘Z）")).disabled(model.busy)
            }
            Button { model.chooseImages() } label: { Label(L10n.text("导入截图"), systemImage: "plus") }.keyboardShortcut("i").disabled(model.busy)
            Menu {
                Button(ExportFormat.docx.label + "…") { model.export(.docx) }
                Button(ExportFormat.analysisDocx.label + "…") { model.export(.analysisDocx) }
                Button(ExportFormat.markdown.label + "…") { model.export(.markdown) }
                Button(L10n.text("PDF 文档…")) { model.export(.pdf) }
                Menu(L10n.text("其他格式")) {
                    Button(L10n.text("纯文本（文字与素材说明）…")) { model.export(.txt) }
                }
                Divider(); Button(L10n.text("复制文字")) { model.copyText() }
            } label: { Label(L10n.text("导出文档"), systemImage: "square.and.arrow.up") }
            .menuStyle(.button).fixedSize().disabled(model.busy || model.project.visibleMessages.isEmpty)
            Menu {
                Button(L10n.text("粘贴截图"), systemImage: "doc.on.clipboard") { model.pasteImages() }
                Divider()
                Button(L10n.text("文档设置…"), systemImage: "slider.horizontal.3") { settings = true }
                Menu {
                    Picker(L10n.text("界面外观"), selection: $appearanceMode) {
                        ForEach(AppearanceMode.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                    }.pickerStyle(.inline)
                } label: { Label(L10n.text("外观"), systemImage: "moon") }
                if !empty {
                    Button(model.preview ? L10n.text("返回文字编辑") : L10n.text("预览文档")) { model.preview.toggle() }
                    Toggle(L10n.text("显示已排除消息"), isOn: $model.showExcluded)
                }
                Menu("Language / 语言") {
                    Picker("Language", selection: $appLanguage) { ForEach(AppLanguage.allCases, id: \.rawValue) { Text($0.name).tag($0.rawValue) } }.pickerStyle(.inline)
                }
                Divider()
                Button(L10n.text("新建项目")) { model.newProject() }
                Button(L10n.text("打开项目…")) { model.openProject() }
                Button(L10n.text("保存项目副本…")) { model.saveProject() }
            } label: { Image(systemName: "ellipsis.circle").font(.system(size: 19)) }
            .menuStyle(.borderlessButton).fixedSize().disabled(model.busy).help(L10n.text("更多选项"))
        }.buttonStyle(.bordered).padding(.horizontal, 22).padding(.vertical, 17).background(Theme.paper)
    }
    private var welcome: some View {
        VStack(spacing: 18) {
            Image(systemName: "photo.on.rectangle.angled").font(.system(size: 45, weight: .ultraLight)).foregroundStyle(Theme.green)
            Text(L10n.text("把微信截图拖到这里")).font(.system(size: 24, weight: .medium))
            Text(L10n.text("支持从 Mac“照片”或访达直接拖入多张图片")).foregroundStyle(Theme.muted)
            Button(L10n.text("选择截图…")) { model.chooseImages() }.buttonStyle(.borderedProminent).controlSize(.large).padding(.top, 4)
            Button(L10n.text("或粘贴已复制的截图（⇧⌘V）")) { model.pasteImages() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.green)
            Text(L10n.text("识别后可直接修改文字，再导出 Word 或 PDF")).font(.system(size: 11)).foregroundStyle(Theme.muted).padding(.top, 7)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(36)
    }
    private var sourcePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L10n.text("截图")).font(.system(size: 13, weight: .semibold)); Spacer()
                Button(L10n.text("框选素材")) { model.beginMediaCapture() }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(Theme.green).disabled(model.busy || model.currentShot == nil)
                if let shot = model.currentShot {
                    Menu {
                        Button(L10n.text("放大")) { model.zoom = min(3, model.zoom + 0.5) }
                        Button(L10n.text("缩小")) { model.zoom = max(1, model.zoom - 0.5) }
                        Button(L10n.text("适合宽度")) { model.zoom = 1 }
                        Divider()
                        Button(L10n.text("向前移动")) { model.moveShot(shot.id, by: -1) }
                        Button(L10n.text("向后移动")) { model.moveShot(shot.id, by: 1) }
                        Button(L10n.text("识别范围与设置…")) { settings = true }
                        Button(L10n.text("移除截图…"), role: .destructive) { deleteShot = shot.id }
                    } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().disabled(model.busy)
                }
            }.padding(18)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    ForEach(Array(model.project.screenshots.enumerated()), id: \.element.id) { index, shot in
                        Button {
                            model.selectScreenshot(shot.id)
                        } label: {
                            VStack(spacing: 5) {
                                if let image = model.image(for: shot, thumbnail: true) {
                                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).frame(width: 44, height: 60).clipped().clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                                Text("\(index + 1)").font(.system(size: 10, weight: .medium))
                            }.padding(6).background(model.selectedShot == shot.id ? Theme.pale : .clear, in: RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(.plain).disabled(model.busy).help(shot.filename + L10n.text(" · 拖动可排序"))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(dropShot == shot.id ? Theme.green : .clear, lineWidth: 2))
                        .onDrag { ScreenshotDrag.provider(for: shot.id) }
                        .onDrop(of: [ScreenshotDrag.type], isTargeted: Binding(get: { dropShot == shot.id }, set: { dropShot = $0 ? shot.id : nil })) { providers in
                            guard !model.busy, let provider = providers.first else { return false }
                            provider.loadDataRepresentation(forTypeIdentifier: ScreenshotDrag.type) { data, _ in
                                guard let data, let string = String(data: data, encoding: .utf8), let source = UUID(uuidString: string) else { return }
                                DispatchQueue.main.async { model.moveShot(source, to: shot.id); dropShot = nil }
                            }
                            return true
                        }
                        .contextMenu {
                            Button(L10n.text("向前移动")) { model.moveShot(shot.id, by: -1) }.disabled(model.busy || index == 0)
                            Button(L10n.text("向后移动")) { model.moveShot(shot.id, by: 1) }.disabled(model.busy || index == model.project.screenshots.count - 1)
                            Divider(); Button(L10n.text("移除…"), role: .destructive) { deleteShot = shot.id }.disabled(model.busy)
                        }
                    }
                }.padding(.horizontal, 13).padding(.bottom, 12)
            }.fixedSize(horizontal: false, vertical: true)
            if let shot = model.currentShot, let image = model.image(for: shot) {
                ScrollViewReader { reader in
                    ScrollView([.horizontal, .vertical]) {
                        SourceImage(image: image, shot: shot, messages: model.project.messages.filter { $0.sourceID == shot.id && (!model.proofreading || (!$0.excluded && !$0.reviewed)) }, selected: model.currentMessage, select: { model.select($0) })
                            .frame(width: 280 * model.zoom, height: 280 * model.zoom * CGFloat(shot.height) / CGFloat(max(1, shot.width))).padding(12)
                    }.onChange(of: model.selectedMessage) { _, id in
                        if id != nil { DispatchQueue.main.async { withAnimation { reader.scrollTo("source-active", anchor: .center) } } }
                    }
                }
                if let error = shot.error {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.display(error)).font(.system(size: 11)).foregroundStyle(.orange)
                        Button(L10n.text("重新识别")) { model.rebuildSelected() }.controlSize(.small).disabled(model.busy)
                    }.padding(14)
                }
            } else {
                Text(L10n.text("拖入截图即可对照原图")).font(.system(size: 12)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.background(Theme.paper)
    }
    private var editorHeader: some View {
        VStack(spacing: 12) {
            HStack {
                TextField(L10n.text("文档标题"), text: $model.project.title).textFieldStyle(.plain).font(.system(size: 19, weight: .medium, design: .serif))
                Spacer()
                if !model.preview && !model.proofreading && !model.mediaLibrary {
                    Button { searchVisible.toggle(); if !searchVisible { model.search = "" }; searchFocused = searchVisible } label: { Image(systemName: "magnifyingglass") }.buttonStyle(.plain).help(L10n.text("搜索文字（⌘F）")).keyboardShortcut("f")
                }
                if !model.preview {
                    Button(model.mediaLibrary ? L10n.text("返回文字") : L10n.text("素材夹")) {
                        if model.mediaLibrary { model.mediaLibrary = false } else { searchVisible = false; model.openMediaLibrary() }
                    }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.green)
                    Button(model.proofreading ? L10n.text("退出核对") : L10n.text("快速核对")) {
                        if model.proofreading { model.endProofreading() } else { searchVisible = false; model.startProofreading() }
                    }.buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.green)
                }
                if !model.proofreading && !model.mediaLibrary { Button(model.preview ? L10n.text("编辑文字") : L10n.text("预览")) { model.preview.toggle() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.green) }
            }
            if searchVisible && !model.preview && !model.proofreading && !model.mediaLibrary {
                HStack {
                    TextField(L10n.text("搜索聊天内容"), text: $model.search).textFieldStyle(.roundedBorder).focused($searchFocused)
                    Button { model.search = ""; searchVisible = false } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }.buttonStyle(.plain).help(L10n.text("关闭搜索"))
                }
            }
        }.padding(.horizontal, 24).padding(.vertical, 20).disabled(model.busy)
    }
    private var filteredMessages: [Message] {
        model.project.messages.filter { (model.showExcluded || !$0.excluded) && (model.search.isEmpty || $0.documentText.localizedCaseInsensitiveContains(model.search) || model.project.name(for: $0).localizedCaseInsensitiveContains(model.search)) }
    }
    private var transcript: some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 11) {
                    if model.busy {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small); Text(L10n.display(model.progress)).font(.system(size: 12)); Spacer()
                            if model.canStop { Button(L10n.text("停止")) { model.stopImport() }.controlSize(.small) }
                        }.padding(16).background(Theme.pale, in: RoundedRectangle(cornerRadius: 9))
                    }
                    if model.duplicateCount > 0 {
                        HStack {
                            Text(L10n.text("{0} 条疑似重复消息", [String(describing: model.duplicateCount)])).font(.system(size: 11)).foregroundStyle(Theme.muted)
                            Spacer()
                            Button(L10n.text("排除重复")) { model.hideDuplicateCandidates() }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(Theme.green)
                        }.padding(.vertical, 5)
                    }
                    ForEach(filteredMessages) { m in MessageCard(model: model, message: m).id(m.id) }
                    if filteredMessages.isEmpty && !model.busy { Text(model.search.isEmpty ? L10n.text("没有识别到文字，可调整截图识别范围。") : L10n.text("没有找到匹配文字")).font(.system(size: 12)).foregroundStyle(Theme.muted).padding(.vertical, 30) }
                    Button { model.addMessage() } label: { Label(L10n.text("补充一条消息"), systemImage: "plus").font(.system(size: 11)).foregroundStyle(Theme.green).padding(.vertical, 12) }.buttonStyle(.plain).disabled(model.busy)
                }.padding(.horizontal, 24).padding(.bottom, 20)
            }.onChange(of: model.selectedMessage) { _, id in if let id { withAnimation { reader.scrollTo(id, anchor: .center) } } }
        }
    }
    private var documentPreview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(model.project.title).font(.system(size: 27, weight: .medium, design: .serif)).padding(.bottom, 16)
                Text(L10n.text("参与人：{0}、{1}", [String(describing: model.project.myName), String(describing: model.project.otherName)])).font(.system(size: 11)).foregroundStyle(Theme.muted)
                if !model.project.note.isEmpty { Text(model.project.note).font(.system(size: 12)).foregroundStyle(Theme.muted).padding(.top, 16) }
                Divider().padding(.vertical, 25)
                ForEach(model.project.visibleMessages) { m in
                    if m.speaker == .system { Text(m.text).font(.system(size: 10)).foregroundStyle(Theme.muted).padding(.vertical, 14) }
                    else {
                        Text(model.project.name(for: m)).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.green).padding(.bottom, 7)
                        if m.media != nil, let image = model.mediaImage(for: m) { Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(maxWidth: 420, maxHeight: 300).padding(.bottom, 10) }
                        Text(m.documentText).font(.system(size: 13)).lineSpacing(6).textSelection(.enabled).padding(.bottom, 23)
                    }
                }
            }.frame(maxWidth: 620, alignment: .leading).padding(32).background(Theme.card).padding(.horizontal, 24).padding(.bottom, 24)
        }
    }
    private var footer: some View {
        HStack {
            Text(L10n.display(model.busy ? model.progress : (model.notice ?? model.status))); Spacer()
            if empty { Label(L10n.text("仅在本机处理"), systemImage: "lock") }
            else { Text(L10n.text("{0} 张截图 · {1} 条消息", [String(describing: model.project.screenshots.count), String(describing: model.project.visibleMessages.filter { $0.speaker != .system }.count)])) }
        }.font(.system(size: 10)).foregroundStyle(Theme.muted).padding(.horizontal, 22).padding(.vertical, 10).background(Theme.paper)
    }
}

private struct OptionsSheet: View {
    @ObservedObject var model: Workspace
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.simplifiedChinese.rawValue
    @State private var confirmRebuild = false
    @Environment(\.locale) private var interfaceLocale
    var body: some View {
        let _ = interfaceLocale.identifier
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.text("文档设置")).font(.system(size: 19, weight: .semibold))
            Picker(L10n.text("界面外观"), selection: $appearanceMode) {
                ForEach(AppearanceMode.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
            }.pickerStyle(.segmented)
            Picker(L10n.text("界面语言"), selection: $appLanguage) {
                ForEach(AppLanguage.allCases, id: \.rawValue) { Text($0.name).tag($0.rawValue) }
            }
            Text(L10n.text("切换界面语言不会翻译或修改聊天原文。" )).font(.system(size: 11)).foregroundStyle(Theme.muted)
            Form {
                TextField(L10n.text("标题"), text: $model.project.title)
                TextField(L10n.text("我方称呼"), text: $model.project.myName)
                TextField(L10n.text("对方称呼"), text: $model.project.otherName)
                TextField(L10n.text("文档说明"), text: $model.project.note)
            }.textFieldStyle(.roundedBorder)
            if let shot = model.currentShot {
                DisclosureGroup(L10n.text("截图识别范围")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.text("用于排除状态栏、输入框或键盘，调整后重新识别。")).font(.system(size: 11)).foregroundStyle(Theme.muted)
                        rangeSlider(L10n.text("顶部"), shot: shot, top: true)
                        rangeSlider(L10n.text("底部"), shot: shot, top: false)
                        Button(L10n.text("重新识别当前截图…")) { confirmRebuild = true }
                    }.padding(.top, 12)
                }
            }
            HStack { Spacer(); Button(L10n.text("完成")) { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 420).background(Theme.paper).foregroundStyle(Theme.ink).tint(Theme.green)
        .alert(L10n.text("重新识别这张截图？"), isPresented: $confirmRebuild) {
            Button(L10n.text("取消"), role: .cancel) {}
            Button(L10n.text("重新识别"), role: .destructive) { model.rebuildSelected(); dismiss() }
        } message: { Text(L10n.text("将替换这张截图的文字及手动修改。")) }
    }
    private func rangeSlider(_ title: String, shot: Screenshot, top: Bool) -> some View {
        let value = top ? shot.top : shot.bottom
        let range = top ? 0...min(0.65, shot.bottom - 0.1) : max(0.25, shot.top + 0.1)...1
        return HStack {
            Text(title).font(.system(size: 11))
            Slider(value: Binding(get: { model.project.screenshots.first { $0.id == shot.id }.map { top ? $0.top : $0.bottom } ?? value }, set: { v in
                if let i = model.project.screenshots.firstIndex(where: { $0.id == shot.id }) { if top { model.project.screenshots[i].top = v } else { model.project.screenshots[i].bottom = v } }
            }), in: range)
            Text("\(Int(value * 100))%").font(.system(size: 10, design: .monospaced)).frame(width: 32)
        }
    }
}

private struct MessageCard: View {
    @ObservedObject var model: Workspace
    let message: Message
    @FocusState private var textFocused: Bool
    @State private var editName = false
    @Environment(\.locale) private var interfaceLocale
    var body: some View {
        let _ = interfaceLocale.identifier
        let m = model.project.messages.first { $0.id == message.id } ?? message
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Menu {
                    ForEach(Speaker.allCases.filter { m.media == nil || $0 != .system }, id: \.self) { speaker in Button(speaker.label) { model.edit(m.id) { $0.speaker = speaker }; model.select(m) } }
                } label: { Text(model.project.name(for: m)).font(.system(size: 11, weight: .medium)) }.menuStyle(.borderlessButton).fixedSize()
                if m.reviewed { Image(systemName: "checkmark.circle.fill").font(.system(size: 10)).foregroundStyle(Theme.green).help(L10n.text("已人工核对；修改后会重新待核对")) }
                Spacer()
                if m.duplicateOf != nil { Text(L10n.text("疑似重复")).font(.system(size: 9)).foregroundStyle(Theme.muted) }
                Menu {
                    Button(m.reviewed ? L10n.text("重新核对这条") : L10n.text("核对这条")) { model.startProofreading(from: m.id) }.disabled(m.excluded)
                    Button(L10n.text("修改署名…")) { editName = true }
                    if m.media != nil { Button(L10n.text("在素材夹中整理")) { model.openMediaLibrary(); model.select(m) } }
                    Button(L10n.text("与上一条合并")) { model.mergePrevious(m.id) }.disabled(m.media != nil)
                    Button(L10n.text("按换行拆分")) { model.split(m.id) }.disabled(m.media != nil || !m.text.contains("\n"))
                    Divider()
                    Button(m.excluded ? L10n.text("恢复到文档") : L10n.text("从文档排除")) { model.edit(m.id) { $0.excluded.toggle() } }
                } label: { Image(systemName: "ellipsis").foregroundStyle(Theme.muted) }.menuStyle(.borderlessButton).fixedSize()
            }
            if let media = m.media {
                Label(media.kind.label + (media.favorite ? L10n.text(" · 已收藏") : ""), systemImage: media.kind.symbol).font(.system(size: 10)).foregroundStyle(Theme.green)
                if let image = model.mediaImage(for: m) { Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(maxWidth: .infinity, maxHeight: 230) }
            }
            TextField(m.media == nil ? L10n.text("输入文字…") : L10n.text("素材说明（可选）"), text: Binding(get: { model.project.messages.first { $0.id == m.id }?.text ?? m.text }, set: { value in model.edit(m.id, coalescing: "text") { $0.text = value } }), axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 14)).lineSpacing(5).lineLimit(1...100).focused($textFocused)
                .onChange(of: textFocused) { _, focused in if focused { model.select(m) } }
            if m.excluded { Text(L10n.text("已从文档排除")).font(.system(size: 10)).foregroundStyle(Theme.muted) }
        }.padding(15).background(m.speaker == .system ? Theme.paper.opacity(0.6) : Theme.card, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(model.selectedMessage == m.id ? Theme.green.opacity(0.6) : .clear))
            .opacity(m.excluded ? 0.5 : 1).contentShape(Rectangle()).onTapGesture { model.select(m) }.disabled(model.busy)
            .popover(isPresented: $editName) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.text("这条消息的署名")).font(.headline)
                    TextField(L10n.text("留空时使用默认称呼"), text: Binding(get: { model.project.messages.first { $0.id == m.id }?.customName ?? "" }, set: { value in model.edit(m.id, coalescing: "name") { $0.customName = value } })).textFieldStyle(.roundedBorder)
                    HStack { Spacer(); Button(L10n.text("完成")) { editName = false } }
                }.padding(18).frame(width: 250)
            }
    }
}

private struct SourceImage: View {
    let image: NSImage, shot: Screenshot, messages: [Message], selected: Message?
    let select: (Message) -> Void
    @Environment(\.locale) private var interfaceLocale
    var body: some View {
        let _ = interfaceLocale.identifier
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                Image(nsImage: image).resizable().frame(width: g.size.width, height: g.size.height)
                Rectangle().fill(.black.opacity(0.24)).frame(height: g.size.height * CGFloat(shot.top)).allowsHitTesting(false)
                Rectangle().fill(.black.opacity(0.24)).frame(height: g.size.height * CGFloat(1 - shot.bottom)).offset(y: g.size.height * CGFloat(shot.bottom)).allowsHitTesting(false)
                if let current = selected, current.sourceID == shot.id, let box = current.box {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: g.size.height * CGFloat(box.y))
                        Color.clear.frame(height: max(1, g.size.height * CGFloat(box.height))).id("source-active")
                        Spacer(minLength: 0)
                    }.allowsHitTesting(false)
                }
                ForEach(messages) { m in
                    if let b = m.box {
                        MessageHighlight(box: b, size: g.size, active: selected?.id == m.id).id("source-\(m.id)").onTapGesture { select(m) }
                    }
                }
            }.clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct MessageHighlight: View {
    let box: Box, size: CGSize, active: Bool
    @Environment(\.locale) private var interfaceLocale
    var body: some View {
        let _ = interfaceLocale.identifier
        let width = max(8, size.width * CGFloat(box.width) + 6)
        let height = max(8, size.height * CGFloat(box.height) + 6)
        let x = size.width * CGFloat(box.x) - 3
        let y = size.height * CGFloat(box.y) - 3
        RoundedRectangle(cornerRadius: 3).fill(active ? Color.orange.opacity(0.17) : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(active ? Color.orange : Color.clear, lineWidth: 1.5))
            .frame(width: width, height: height).contentShape(Rectangle()).offset(x: x, y: y)
    }
}
