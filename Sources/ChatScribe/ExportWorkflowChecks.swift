import AppKit
import ChatCore

enum ExportWorkflowChecks {
    @MainActor static func run(folder: URL) async throws {
        let directory = folder.appendingPathComponent("export-workflow-" + UUID().uuidString)
        let model = Workspace(dataDirectory: directory)
        let original = L10n.overrideLanguage
        defer { L10n.overrideLanguage = original; model.flush(); try? FileManager.default.removeItem(at: directory) }
        func verify(_ value: Bool, _ label: String) throws { if !value { throw OCRFailure("Export workflow: " + label) } }
        func wait() async throws {
            let deadline = Date().addingTimeInterval(60)
            while model.busy && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
            try verify(!model.busy, "worker timed out")
        }
        model.loadProject(folder.appendingPathComponent("图文示例项目.liaoji"))
        let snapshot = model.project
        L10n.overrideLanguage = .english
        let destination = folder.appendingPathComponent("background-export.md")
        model.performExport(.markdown, to: destination, reveal: false)
        try verify(model.busy, "export starts a background worker")
        model.edit(snapshot.messages[0].id) { $0.text = "must not change during export" }
        L10n.overrideLanguage = .korean
        try await wait()
        let content = try String(contentsOf: destination, encoding: .utf8)
        try verify(content.contains("Participants:") && content.contains("Optional AI analysis prompt") && !content.contains("선택 가능한 AI 분석 프롬프트"), "one export keeps its initial language despite a preference change")
        try verify(model.project == snapshot && model.alert == nil, "export does not alter the conversation")
        model.performExport(.docx, to: folder, reveal: false)
        try await wait()
        try verify(model.alert != nil && model.progress.isEmpty && model.project == snapshot, "failed write restores editable state and leaves the project unchanged")
        model.alert = nil
        let before = Set(try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix("Liaoji-assets-") })
        do { try MarkdownExport.write(snapshot, to: folder); throw OCRFailure("Expected a directory write failure") }
        catch let error as OCRFailure { throw error }
        catch { }
        let after = Set(try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix("Liaoji-assets-") })
        try verify(before == after, "a late Markdown write failure cleans only its new image folder")
        print("PASS: background exports, language snapshot, blocked conflicting edits, failure recovery and Markdown attachment cleanup")
    }
}
