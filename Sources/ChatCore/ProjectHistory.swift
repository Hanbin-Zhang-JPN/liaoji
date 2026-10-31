import Foundation

/// Bounded project snapshots share their immutable image Data buffers.
public struct ProjectHistory {
    private struct Entry { let project: Project; let label: String }
    private var past: [Entry] = []
    private var future: [Entry] = []
    private var lastKey: String?
    private var lastTime = -Double.infinity
    private let limit: Int
    public init(limit: Int = 30) { self.limit = max(1, limit) }
    public var undoLabel: String? { past.last?.label }
    public var redoLabel: String? { future.last?.label }
    public mutating func record(_ project: Project, label: String, key: String? = nil, time: TimeInterval = Date.timeIntervalSinceReferenceDate) {
        let coalesced = key != nil && key == lastKey && time >= lastTime && time - lastTime < 0.8 && !past.isEmpty && future.isEmpty
        if !coalesced { past.append(Entry(project: project, label: label)); if past.count > limit { past.removeFirst() } }
        future.removeAll(); lastKey = key; lastTime = time
    }
    public mutating func endCoalescing() { lastKey = nil; lastTime = -Double.infinity }
    public mutating func undo(current: Project) -> Project? {
        guard let entry = past.popLast() else { return nil }
        future.append(Entry(project: current, label: entry.label)); endCoalescing(); return entry.project
    }
    public mutating func redo(current: Project) -> Project? {
        guard let entry = future.popLast() else { return nil }
        past.append(Entry(project: current, label: entry.label)); endCoalescing(); return entry.project
    }
    public mutating func clear() { past.removeAll(); future.removeAll(); endCoalescing() }
}
