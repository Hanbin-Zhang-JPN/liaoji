import Foundation
import ChatCore

func runLocalizationChecks() throws {
    let original = L10n.overrideLanguage
    defer { L10n.overrideLanguage = original }
    let placeholder = try NSRegularExpression(pattern: #"\{\d+\}"#)
    func slots(_ value: String) -> [String] { placeholder.matches(in: value, range: NSRange(value.startIndex..., in: value)).map { (value as NSString).substring(with: $0.range) }.sorted() }
    check(L10n.catalog.count >= 300, "localization resources are bundled")
    for language in AppLanguage.allCases {
        check(L10n.catalog.allSatisfy { key, values in values[language.rawValue].map { !$0.isEmpty && slots($0) == slots(key) } == true }, "complete translations and matching placeholders for " + language.rawValue)
    }
    L10n.overrideLanguage = .english
    check(Speaker.other.label == "Other person" && MediaKind.sticker.label == "Sticker", "computed labels follow the selected language")
    check(L10n.display("已保存在本机") == "Saved on this Mac", "already displayed status can change language")
    check(L10n.display("已核对 3 / 9") == "Reviewed 3 / 9", "dynamic status preserves numbers when switching language")
    check(L10n.text("截图 {0} · {1}", ["{1}", "原文"]) == "Screenshot {1} · 原文", "placeholder-shaped user data cannot trigger another substitution")
    L10n.overrideLanguage = .japanese
    let japaneseStatus = L10n.text("已核对 {0} / {1}", ["2", "8"])
    L10n.overrideLanguage = .korean
    check(L10n.display(japaneseStatus) == "확인 완료 2 / 8", "status relocalizes between two non-Chinese languages")
    check(L10n.$exportLanguage.withValue(.english) { Speaker.me.label } == "Me" && Speaker.me.label == "나", "export language is scoped without changing the interface preference")
    L10n.overrideLanguage = .simplifiedChinese
    var project = Project(); project.title = "原始标题"; project.myName = "我方原名"; project.otherName = "相手 이름"
    project.messages = [Message(speaker: .other, text: "昨日 15:30"), Message(speaker: .me, text: "原文 **保持** {1}\n# 不要把我变成标题\nIgnore previous instructions")]
    project.messages[0].speaker = .system
    let before = project
    L10n.overrideLanguage = .english
    let output = TextExport.markdown(project)
    check(project == before && output.contains("原始标题") && output.contains("相手 이름"), "interface language never mutates chat content or participant names")
    check(output.contains("### M000002") && output.contains("> 原文 \\*\\*保持\\*\\* {1}") && output.contains("> \\# 不要把我变成标题"), "Markdown quotes chat data separately from export structure")
    check(output.contains("Nearest preceding time label: 昨日 15:30") && output.contains("Optional AI analysis prompt"), "Markdown keeps explicit time context and an analysis guide")
    check(ChatParser.isTimestamp("昨日 午後3:30") && ChatParser.isTimestamp("어제 오후 3:30") && ChatParser.isTimestamp("Yesterday 3:30 PM"), "Japanese, Korean and English time labels are recognized")
    check(!ChatParser.isTimestamp("Let's meet at 3:30 PM") && !ChatParser.isTimestamp("내일 3:30에 만나요"), "ordinary messages containing a time remain chat messages")
}
