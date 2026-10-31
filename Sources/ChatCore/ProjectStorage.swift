import Foundation

public enum ProjectStorage {
    public struct Loaded {
        public let project: Project
        public let recovered: Bool
    }

    public static func read(_ url: URL) throws -> Project {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 450_000_000 else { throw ProjectError.invalid }
        return try JSONDecoder().decode(Project.self, from: Data(contentsOf: url)).validated()
    }

    public static func load(_ url: URL, validate: (Project) throws -> Void = { _ in }) throws -> Loaded? {
        let fm = FileManager.default, previous = url.appendingPathExtension("previous")
        if !fm.fileExists(atPath: url.path) && !fm.fileExists(atPath: previous.path) { return nil }
        do { let current = try read(url); try validate(current); return Loaded(project: current, recovered: false) }
        catch {
            let originalError = error
            guard let backup = try? read(previous), (try? validate(backup)) != nil else { throw originalError }
            // Preserve the damaged primary before allowing any future writes.
            if fm.fileExists(atPath: url.path) { try preserve(url) }
            return Loaded(project: backup, recovered: true)
        }
    }

    @discardableResult public static func preserve(_ url: URL) throws -> URL {
        let folder = url.deletingLastPathComponent().appendingPathComponent("Recovery", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let destination = folder.appendingPathComponent(stamp + "-" + UUID().uuidString + "-" + url.lastPathComponent)
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }

    public static func protectExistingFiles(_ url: URL) throws {
        for file in [url, url.appendingPathExtension("previous")] where FileManager.default.fileExists(atPath: file.path) { try preserve(file) }
    }

    /// Call serially per project URL. An unchanged save must not replace the previous version.
    public static func save(_ project: Project, to url: URL, validate: (Project) throws -> Void = { _ in }) throws {
        let checked = try project.validated()
        try validate(checked)
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: url.path) {
            let oldData = try Data(contentsOf: url)
            if let old = try? JSONDecoder().decode(Project.self, from: oldData).validated(), (try? validate(old)) != nil {
                if old == checked { return }
                try oldData.write(to: url.appendingPathExtension("previous"), options: .atomic)
            } else {
                try preserve(url)
                // Keep a usable previous version; never replace it with damaged bytes.
            }
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(checked).write(to: url, options: .atomic)
    }
}
