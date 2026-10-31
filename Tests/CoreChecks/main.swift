import Foundation
import ChatCore

L10n.overrideLanguage = .simplifiedChinese

var checks = 0
func check(_ condition: @autoclosure () throws -> Bool, _ label: String) rethrows {
    guard try condition() else { fputs("FAIL: \(label)\n", stderr); exit(1) }
    checks += 1
}
func line(_ s: String, _ y: Double, bubble: Int? = nil, side: Speaker? = nil, x: Double = 0.16) -> OCRLine {
    OCRLine(s, box: Box(x: x, y: y, width: 0.4, height: 0.025), bubble: bubble, side: side)
}
var shot = Screenshot(filename: "1.png", imageData: Data([0]), width: 750, height: 1624)
shot.lines = [line("手机状态", 0.02), line("星期五 10:30", 0.16, x: 0.3), line("你好，", 0.25, bubble: 0, side: .other), line("周末一起去公园吧。", 0.28, bubble: 0, side: .other), line("好的，下午两点见。", 0.4, bubble: 1, side: .me), line("键盘", 0.97)]
let parsed = ChatParser.parse(shot)
check(parsed.count == 3, "crop header/footer and merge bubble lines")
check(parsed[0].speaker == .system, "timestamp")
check(parsed[1].text == "你好，\n周末一起去公园吧。", "multiline order")
check(parsed[2].speaker == .me, "right bubble sender")
check(parsed[1].box!.height > 0.05, "merged source box")
check(ChatParser.isTimestamp("昨天 下午3:05"), "Chinese date/time")
check(!ChatParser.isTimestamp("我们 3:05 见"), "conversation is not timestamp")
check(!ChatParser.isTimestamp("25元"), "numbers are not timestamps")
var p = Project(); p.title = "聊天 *记录*"; p.screenshots = [shot]
p.messages = parsed
var second = Screenshot(filename: "2.png", imageData: Data([1]), width: 750, height: 1624)
p.screenshots.append(second)
for m in parsed.dropFirst() { p.messages.append(Message(sourceID: second.id, speaker: m.speaker, text: m.text)) }
p.messages.append(Message(sourceID: second.id, speaker: .other, text: "好的，下次见"))
ChatParser.markOverlaps(&p)
check(p.messages.filter { $0.duplicateOf != nil }.count == 2, "exact adjacent screenshot overlap")
check(p.visibleMessages.count == 6, "overlap never silently deletes")
p.messages[4].excluded = true
check(!TextExport.plain(p).contains("手机状态"), "header excluded from text")
check(TextExport.markdown(p).hasPrefix("# 聊天 \\*记录\\*"), "Markdown escapes title")
p.messages[1].customName = "小李"
check(TextExport.plain(p).contains("小李\n你好"), "per-message group sender")
let encoded = try JSONEncoder().encode(p)
let decoded = try JSONDecoder().decode(Project.self, from: encoded).validated()
check(decoded.messages == p.messages && decoded.screenshots[0].imageData == shot.imageData, "portable project round trip")
var invalid = p; invalid.screenshots[0].bottom = -1
check((try? invalid.validated()) == nil, "invalid crop rejected")
var repeated = Project(); repeated.screenshots = [shot, second]
repeated.messages = [Message(sourceID: shot.id, speaker: .other, text: "好的"), Message(sourceID: second.id, speaker: .other, text: "好的")]
ChatParser.markOverlaps(&repeated)
check(repeated.messages.allSatisfy { $0.duplicateOf == nil }, "common single response not deduplicated")
var history = ProjectHistory(limit: 2)
var state = Project()
history.record(state, label: "写字", key: "message", time: 1)
state.title = "甲"
history.record(state, label: "写字", key: "message", time: 1.2)
state.title = "甲乙"
check(history.undo(current: state)?.title == "微信聊天记录", "continuous typing coalesces to one undo")
check(history.redo(current: Project())?.title == "甲乙", "redo restores final typed value")
history.endCoalescing()
history.record(state, label: "排除", time: 2)
state.note = "一条备注"
let beforeNote = history.undo(current: state)!
check(beforeNote.note.isEmpty && beforeNote.title == "甲乙", "structural operation is separate from typing")
history.record(beforeNote, label: "新编辑", time: 3)
check(history.redoLabel == nil, "new edit after undo discards redo branch")
history.clear()
check(history.undo(current: state) == nil && history.redoLabel == nil, "history clears between projects")
for i in 0..<4 { state.title = "\(i)"; history.record(state, label: "编辑", time: Double(i)) }
check(history.undo(current: state)?.title == "3", "latest history entry retained")
check(history.undo(current: state)?.title == "2" && history.undo(current: state) == nil, "bounded undo history")
var named = Project(); named.screenshots = [shot, second]
for source in [shot.id, second.id] {
    for text in ["这是第一条完整的群聊消息", "这是第二条完整的群聊消息"] {
        var item = Message(sourceID: source, speaker: .other, text: text)
        item.customName = source == shot.id ? "小李" : "小王"
        named.messages.append(item)
    }
}
ChatParser.markOverlaps(&named)
check(named.messages.allSatisfy { $0.duplicateOf == nil }, "different group senders are not overlap candidates")
var punctuation = Project(); punctuation.screenshots = [shot, second]
for (source, texts) in [(shot.id, ["金额为 123.45 元", "第二条相同的完整消息"]), (second.id, ["金额为 12345 元", "第二条相同的完整消息"])] {
    for text in texts { punctuation.messages.append(Message(sourceID: source, speaker: .other, text: text)) }
}
ChatParser.markOverlaps(&punctuation)
check(punctuation.messages.allSatisfy { $0.duplicateOf == nil }, "decimal punctuation cannot be ignored during overlap detection")
punctuation.messages[2].text = "金额为 123.45 元"
ChatParser.markOverlaps(&punctuation)
check(punctuation.messages.filter { $0.duplicateOf != nil }.count == 2, "exact punctuation overlap still detected")
punctuation.messages[0].excluded = true
ChatParser.markOverlaps(&punctuation)
check(punctuation.messages.dropFirst(2).allSatisfy { $0.duplicateOf == nil }, "excluded originals cannot mark remaining copies as duplicate")
var casing = punctuation
casing.messages[0].excluded = false
casing.messages[0].text = "密码为 AbCd1234"
casing.messages[2].text = "密码为 abcd1234"
ChatParser.markOverlaps(&casing)
check(casing.messages.allSatisfy { $0.duplicateOf == nil }, "case-sensitive chat content is preserved")
var jitter = shot
jitter.lines = [OCRLine("right", box: Box(x: 0.45, y: 0.3, width: 0.15, height: 0.025), bubble: 0, side: .other), OCRLine("left", box: Box(x: 0.16, y: 0.302, width: 0.15, height: 0.025), bubble: 0, side: .other)]
check(ChatParser.parse(jitter).first?.text == "left right", "slightly misaligned same-row text reads left to right")
var orderTest = Project(); orderTest.screenshots = [shot, second]
orderTest.messages = [Message(sourceID: second.id, speaker: .other, text: "later screenshot"), Message(speaker: .me, text: "manual tail")]
let newlyRecognized = Message(sourceID: shot.id, speaker: .other, text: "recovered first screenshot")
orderTest.replaceMessages(for: shot.id, with: [newlyRecognized])
check(orderTest.messages.map(\.text) == ["recovered first screenshot", "later screenshot", "manual tail"], "retry of formerly empty screenshot respects screenshot order")
try runStorageChecks()
check(parsed[1].originalText == parsed[1].text, "OCR baseline keeps multiline original text")
var proofProject = Project()
var plainMessage = Message(speaker: .other, text: "一条清晰的普通消息"); plainMessage.box = Box(x: 0.1, y: 0.2, width: 0.4, height: 0.03); plainMessage.sourceID = shot.id
var uncertain = plainMessage; uncertain.id = UUID(); uncertain.confidence = 0.5
var numeric = plainMessage; numeric.id = UUID(); numeric.text = "金额 123.45 元"
var done = uncertain; done.id = UUID(); done.reviewed = true
var excluded = uncertain; excluded.id = UUID(); excluded.excluded = true
proofProject.screenshots = [shot]; proofProject.messages = [plainMessage, uncertain, numeric, done, excluded]
check(Proofreading.queue(in: proofProject, scope: .pending).count == 3, "review queue excludes confirmed and excluded messages")
check(Proofreading.queue(in: proofProject, scope: .attention).map(\.id) == [uncertain.id, numeric.id], "attention queue is advisory and preserves order")
check(Proofreading.reasons(for: plainMessage).isEmpty, "high-confidence ordinary text is not labeled as an error")
check(Proofreading.reasons(for: numeric).contains("含数字或时间"), "numeric content gets an explicit check reminder")
var baseline = parsed[1]; baseline.text = "手动修改后的文字"
check(Proofreading.originalText(for: baseline, in: p) == parsed[1].originalText, "manual edits do not overwrite OCR baseline")
baseline.originalText = nil
check(Proofreading.originalText(for: baseline, in: p) == parsed[1].text, "older projects recover original text from source OCR lines")
var blankProject = Project(); blankProject.messages = [Message(speaker: .me, text: " \n "), Message(speaker: .other, text: "有效文字")]
check(blankProject.visibleMessages.map(\.text) == ["有效文字"], "blank drafts do not become exported messages")
var mediaProject = Project(); mediaProject.version = 2; mediaProject.screenshots = [shot, second]
let beforeMedia = Message(sourceID: shot.id, speaker: .other, text: "前文", box: Box(x: 0.1, y: 0.2, width: 0.3, height: 0.02))
let afterMedia = Message(sourceID: shot.id, speaker: .me, text: "后文", box: Box(x: 0.6, y: 0.6, width: 0.3, height: 0.02))
var mediaItem = Message(sourceID: shot.id, speaker: .other, text: "", box: Box(x: 0.15, y: 0.3, width: 0.5, height: 0.2))
mediaItem.media = ChatMedia(kind: .sticker, keywords: "开心", favorite: true)
mediaProject.messages = [beforeMedia, afterMedia]; mediaProject.insertLocatedMessage(mediaItem)
check(mediaProject.messages.map(\.id) == [beforeMedia.id, mediaItem.id, afterMedia.id], "media inserts at original screenshot position")
check(mediaProject.visibleMessages.count == 3, "media without caption is still exported")
check(TextExport.plain(mediaProject).contains("[表情包]\n关键词：开心"), "plain export preserves media type and keywords")
check(Proofreading.reasons(for: mediaItem).isEmpty, "empty media caption is not an empty-text error")
check(Proofreading.originalText(for: mediaItem, in: mediaProject) == nil, "media does not borrow unrelated OCR as baseline")
let mediaDecoded = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(mediaProject)).validated()
check(mediaDecoded == mediaProject, "media metadata round trip")
var wrongVersion = mediaProject; wrongVersion.version = 1
check((try? wrongVersion.validated()) == nil, "media requires new project version to prevent old-app data loss")
var missingSource = mediaProject; missingSource.messages[1].sourceID = nil
check((try? missingSource.validated()) == nil, "orphan media rejected")
var wrongSpeaker = mediaProject; wrongSpeaker.messages[1].speaker = .system
check((try? wrongSpeaker.validated()) == nil, "media requires a sending participant")
var wrongBox = mediaProject; wrongBox.messages[1].box = nil
check((try? wrongBox.validated()) == nil, "media requires crop coordinates")
mediaProject.replaceMessages(for: shot.id, with: [beforeMedia, afterMedia])
check(mediaProject.mediaMessages.map(\.id) == [mediaItem.id], "re-OCR replacement retains saved media")
var legacy = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
legacy["messages"] = (legacy["messages"] as! [[String: Any]]).map { item in var copy = item; copy.removeValue(forKey: "media"); return copy }
let oldProject = try JSONDecoder().decode(Project.self, from: JSONSerialization.data(withJSONObject: legacy)).validated()
check(oldProject.messages.allSatisfy { $0.media == nil }, "pre-media projects remain compatible")
var retryMedia = mediaDecoded
var hiddenOCR = Message(sourceID: shot.id, speaker: .other, text: "人工改过的字", box: Box(x: 0.2, y: 0.34, width: 0.25, height: 0.03))
hiddenOCR.originalText = "型号 AbC123.45"; hiddenOCR.excluded = true
retryMedia.messages.append(hiddenOCR)
var repeatedOCR = hiddenOCR; repeatedOCR.id = UUID(); repeatedOCR.excluded = false; repeatedOCR.text = hiddenOCR.originalText!
var changedOCR = repeatedOCR; changedOCR.id = UUID(); changedOCR.text = "型号 AbC12345"; changedOCR.originalText = changedOCR.text
var elsewhereOCR = repeatedOCR; elsewhereOCR.id = UUID(); elsewhereOCR.box?.y = 0.44
var partialOCR = repeatedOCR; partialOCR.id = UUID(); partialOCR.box?.x = 0.12
retryMedia.replaceMessages(for: shot.id, with: [beforeMedia, repeatedOCR, changedOCR, elsewhereOCR, partialOCR, afterMedia])
check(retryMedia.messages.first { $0.id == repeatedOCR.id }!.excluded, "re-OCR retains excluded original text inside an active media region")
check(!retryMedia.messages.first { $0.id == changedOCR.id }!.excluded, "different OCR content is never hidden by a media exclusion")
check(!retryMedia.messages.first { $0.id == elsewhereOCR.id }!.excluded, "same words at another location are not hidden")
check(!retryMedia.messages.first { $0.id == partialOCR.id }!.excluded, "partial overlap with media does not hide a full message")
var excludedMedia = mediaDecoded; excludedMedia.messages[1].excluded = true; excludedMedia.messages.append(hiddenOCR)
excludedMedia.replaceMessages(for: shot.id, with: [repeatedOCR])
check(!excludedMedia.messages.first { $0.id == repeatedOCR.id }!.excluded, "excluded media does not keep replacement OCR hidden")
check(Box(x: 0.1, y: 0.2, width: 0.2, height: 0.3).encloses(Box(x: 0.1, y: 0.2, width: 0.2, height: 0.3)), "exact crop containment accepts shared floating point edges")
try runLocalizationChecks()
print("PASS: \(checks) core checks")
