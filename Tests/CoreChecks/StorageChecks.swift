import Foundation
import ChatCore

func runStorageChecks() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("Liaoji-Storage-Checks-" + UUID().uuidString)
    let url = root.appendingPathComponent("workspace.liaoji"), previous = url.appendingPathExtension("previous")
    defer { try? FileManager.default.removeItem(at: root) }
    var first = Project(); first.title = "第一版"
    var second = first; second.title = "第二版"
    try ProjectStorage.save(first, to: url)
    try check(try ProjectStorage.read(url) == first, "first save round trip")
    try ProjectStorage.save(second, to: url)
    try check(try ProjectStorage.read(previous) == first, "previous version retained")
    try ProjectStorage.save(second, to: url)
    try ProjectStorage.save(second, to: url)
    try check(try ProjectStorage.read(previous) == first, "unchanged close/flush never overwrites useful backup")
    let broken = Data("{ damaged project".utf8)
    try broken.write(to: url)
    let recovered = try ProjectStorage.load(url)!
    check(recovered.recovered && recovered.project == first, "damaged primary restores valid previous")
    let copies = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("Recovery"), includingPropertiesForKeys: nil)
    try check(try copies.contains { try Data(contentsOf: $0) == broken }, "damaged original preserved before recovery")
    try ProjectStorage.save(recovered.project, to: url)
    try check(try ProjectStorage.read(previous) == first, "recovery never replaces good backup with broken bytes")
    try check(try ProjectStorage.read(url) == first, "recovered project can be saved")
    var invalid = first
    invalid.messages.append(Message(sourceID: UUID(), speaker: .other, text: "orphan"))
    check((try? ProjectStorage.save(invalid, to: url)) == nil, "invalid project cannot overwrite saved project")
    try check(try ProjectStorage.read(url) == first, "saved data survives rejected write")
    var invalidBox = first
    invalidBox.messages.append(Message(speaker: .me, text: "bad box", box: Box(x: .nan, y: 0, width: 1, height: 1)))
    check((try? invalidBox.validated()) == nil, "nonfinite source highlight rejected")
    let brokenBackup = Data("bad backup".utf8)
    try broken.write(to: url); try brokenBackup.write(to: previous)
    check((try? ProjectStorage.load(url)) == nil, "both corrupt versions are not silently replaced")
    try ProjectStorage.protectExistingFiles(url)
    let protected = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("Recovery"), includingPropertiesForKeys: nil)
    try check(try protected.contains { try Data(contentsOf: $0) == brokenBackup }, "previous file preserved before starting fresh")
    try ProjectStorage.save(second, to: url)
    try check(try ProjectStorage.read(url) == second, "fresh project can save after damaged files are protected")
    try ProjectStorage.save(first, to: url)
    var metadataValidButRejected = first; metadataValidButRejected.title = "invalid-image"
    try JSONEncoder().encode(metadataValidButRejected).write(to: url)
    let imageCheck: (Project) throws -> Void = { if $0.title == "invalid-image" { throw ProjectError.invalid } }
    let customRecovered = try ProjectStorage.load(url, validate: imageCheck)!
    check(customRecovered.project == second, "content validation participates in fallback")
    try ProjectStorage.save(customRecovered.project, to: url, validate: imageCheck)
    try check(try ProjectStorage.read(previous) == second, "recovery from content damage protects good previous")
}
