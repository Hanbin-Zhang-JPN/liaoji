import Foundation
import ChatCore

enum MarkdownExport {
    static func write(_ project: Project, to destination: URL) throws {
        let parent = destination.deletingLastPathComponent()
        let assets = parent.appendingPathComponent("Liaoji-assets-" + UUID().uuidString, isDirectory: true)
        var paths: [UUID: String] = [:], created = false
        do {
            if !project.mediaMessages.isEmpty { try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: false); created = true }
            var bytes = 0
            for entry in Transcript.entries(project) where entry.message.media != nil {
                let data = try MediaImages.png(MediaImages.crop(entry.message, in: project, maximum: 3600))
                bytes += data.count
                guard bytes <= 300_000_000 else { throw OCRFailure(L10n.text("素材导出超过 300 MB，请缩小筛选范围分批导出。")) }
                let name = entry.number + ".png"
                try data.write(to: assets.appendingPathComponent(name), options: .atomic)
                paths[entry.message.id] = assets.lastPathComponent + "/" + name
            }
            try Data(TextExport.markdown(project, mediaPaths: paths).utf8).write(to: destination, options: .atomic)
        } catch {
            if created { try? FileManager.default.removeItem(at: assets) }
            throw error
        }
    }
}
