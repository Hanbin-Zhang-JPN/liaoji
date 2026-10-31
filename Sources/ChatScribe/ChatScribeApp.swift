import SwiftUI
import AppKit
import ChatCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--self-test") {
            NSApplication.shared.setActivationPolicy(.prohibited)
            NSApplication.shared.windows.forEach { $0.orderOut(nil) }
            return
        }
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !CommandLine.arguments.contains("--self-test") }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        CommandLine.arguments.contains("--self-test") ? .terminateCancel : .terminateNow
    }
}

@main struct ChatScribeApp: App {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.simplifiedChinese.rawValue
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = Workspace(dataDirectory: CommandLine.arguments.contains("--self-test") ? FileManager.default.temporaryDirectory.appendingPathComponent("Liaoji-Headless-" + UUID().uuidString) : nil)
    init() {
        if let index = CommandLine.arguments.firstIndex(of: "--make-icon"), index + 1 < CommandLine.arguments.count {
            do { try SelfChecks.makeIcon(at: CommandLine.arguments[index + 1]); exit(0) }
            catch { fputs(L10n.text("图标生成失败：{0}\n", [String(describing: error)]), stderr); exit(1) }
        }
        if CommandLine.arguments.contains("--self-test") {
            Task {
                do { try await SelfChecks.run(); exit(0) }
                catch { fputs(L10n.text("验证失败：{0}\n", [String(describing: error)]), stderr); exit(1) }
            }
        }
    }
    var body: some Scene {
        let _ = appLanguage
        WindowGroup(L10n.text("聊迹 · 微信截图转文档")) {
            if !CommandLine.arguments.contains("--self-test") {
                PhotoDropHost(model: model).frame(minWidth: 820, minHeight: 620)
                .onOpenURL { if !model.busy { model.loadProject($0) } }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.flush() }
            }
        }.defaultSize(width: 1040, height: 780).windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L10n.text("新建项目")) { model.newProject() }.keyboardShortcut("n").disabled(model.busy)
                Button(L10n.text("打开项目…")) { model.openProject() }.keyboardShortcut("o").disabled(model.busy)
                Button(L10n.text("保存完整项目…")) { model.saveProject() }.keyboardShortcut("s").disabled(model.busy)
                Divider()
                Button(L10n.text("导入微信截图…")) { model.chooseImages() }.keyboardShortcut("i").disabled(model.busy)
                Button(L10n.text("粘贴截图")) { model.pasteImages() }.keyboardShortcut("v", modifiers: [.command, .shift]).disabled(model.busy)
            }
            CommandGroup(replacing: .undoRedo) {
                Button(model.undoLabel.map { L10n.text("撤销") + L10n.display($0) } ?? L10n.text("撤销")) { model.undo() }.keyboardShortcut("z").disabled(model.busy || model.undoLabel == nil)
                Button(model.redoLabel.map { L10n.text("重做") + L10n.display($0) } ?? L10n.text("重做")) { model.redo() }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(model.busy || model.redoLabel == nil)
            }
            CommandMenu(L10n.text("整理")) {
                Button(L10n.text("框选图片或表情…")) { model.beginMediaCapture() }.keyboardShortcut("m", modifiers: [.command, .shift]).disabled(model.busy || model.currentShot == nil)
                Button(L10n.text("打开素材夹")) { model.openMediaLibrary() }.disabled(model.busy)
                Divider()
                Button(L10n.text("添加消息")) { model.addMessage() }.keyboardShortcut("n", modifiers: [.command, .shift]).disabled(model.busy)
                Button(L10n.text("复制全部文字")) { model.copyText() }.keyboardShortcut("c", modifiers: [.command, .shift])
                Divider()
                Button(L10n.text("打开本机数据与归档")) { model.showDataFolder() }
            }
            CommandMenu(L10n.text("核对")) {
                Button(model.proofreading ? L10n.text("退出快速核对") : L10n.text("开始快速核对")) {
                    if model.proofreading { model.endProofreading() } else { model.startProofreading() }
                }.keyboardShortcut("r", modifiers: [.command, .shift]).disabled(model.busy || model.project.messages.isEmpty)
                Button(L10n.text("上一条待核对")) { model.navigateProofreading(by: -1) }.keyboardShortcut("[").disabled(model.busy || !model.proofreading || !model.canNavigateProofreading(by: -1))
                Button(L10n.text("下一条待核对")) { model.navigateProofreading(by: 1) }.keyboardShortcut("]").disabled(model.busy || !model.proofreading || !model.canNavigateProofreading(by: 1))
                Button(L10n.text("确认并核对下一条")) { model.confirmProofreading() }.keyboardShortcut(.return, modifiers: .command).disabled(model.busy || !model.proofreading || model.proofMessage == nil)
            }
            CommandMenu(L10n.text("导出")) { ForEach(ExportFormat.allCases, id: \.self) { f in Button(f.label + "…") { model.export(f) }.disabled(model.busy || model.project.visibleMessages.isEmpty) } }
            CommandGroup(replacing: .help) {
                Button(L10n.text("使用说明")) {
                    let alert = NSAlert(); alert.messageText = L10n.text("聊迹 · 使用说明")
                    alert.informativeText = L10n.text("1. 从 Mac“照片”或访达拖入微信截图，或按 ⌘I 选择文件。\n2. 左侧“框选素材”可保存图片或表情，按原图位置插入记录；“素材夹”支持分类、关键词、收藏与批量导出。截图只能保存静态画面。\n3. “快速核对”可放大原文，⌘↩ 确认并继续；⌘[ / ⌘] 切换但不确认。\n4. Word 和 PDF 包含图片；Markdown、TXT 和复制文字包含素材说明。\n\n称呼和深色外观在右上角“更多”中。项目自动保存在本机，⌘S 可另存含截图和素材的完整项目。含素材的项目需要聊迹 1.5 或更新版本。\n\nOCR 及疑点提示仅供辅助，请以原图为准；语音和复杂卡片需人工补充。")
                    alert.runModal()
                }
                Button(L10n.text("打开示例项目")) { model.loadDemo() }.disabled(model.busy)
            }
        }
    }
}
