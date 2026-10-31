# Liaoji 聊迹

[简体中文](README.md) · English

A native macOS app for turning WeChat screenshots into editable, readable conversation documents. OCR runs locally with Apple Vision. No account, server, API key, telemetry, or remote AI request is required.

## What it does

- Import multiple screenshots from Finder, Photos, a file picker, or the clipboard.
- Review recognized text beside its screenshot, zoom into each message, and track manual review. Edits make a reviewed message pending again.
- Crop pictures and stickers into the conversation at their screenshot positions. Organize them by category, notes, keywords, and favorites; return to the source and export selected media.
- Export a reading copy in Word, a Word document prepared for AI context/reply analysis, PDF, Markdown with real image attachments, or plain text.
- Choose Simplified Chinese, Traditional Chinese, Japanese, English, or Korean. The interface language does not translate or mutate your conversation.
- Use light, dark, or system appearance. Undo/redo, conservative overlap hints, local auto-save, backups, and recovery are included.

## Requirements and launch

macOS 14 or newer and Apple Command Line Tools are required to build. The script produces a native build for the current Mac architecture; no full Xcode project or third-party runtime dependency is required.

```sh
./scripts/build-app.sh
open dist/聊迹.app
```

The local app is ad-hoc signed and is not Apple-notarized. A copy downloaded on another Mac may require the normal macOS first-launch approval. The script also creates a ZIP in `dist/`.

## Everyday workflow

1. Import screenshots with **⌘I**, drag and drop, or **⇧⌘V**. Ordinary **⌘V** still pastes text into an editor.
2. Correct the text, speaker, and per-message name. **Quick Review** (**⇧⌘R**) shows the original crop. **⌘↩** confirms and advances; **⌘[ / ⌘]** navigate without confirming.
3. Choose **Crop Media** (**⇧⌘M**) for a picture or sticker. Check the preview, category, sender, optional note, and keywords. OCR text inside the image is kept unless you explicitly choose to exclude it.
4. Export the document, or save a complete `.liaoji` project with **⌘S**. Open a saved project with **⌘O**.

Language is in **More → Language / 语言** and in Document Settings. Some macOS-owned dialog controls follow the operating system language.

## Export choices

**Word · Reading copy** uses real Word title/heading styles, message numbers, sender names, time labels, review status, screenshot sources, and embedded pictures. It is intended for reading, navigation, and keeping a conversation.

**Word · AI analysis** preserves the transcript and adds a separate editable analysis brief. The brief asks an AI to cite message numbers, separate facts from interpretations, flag missing context, and offer reply options without inventing commitments. The app does not send this file to an AI or produce a psychological assessment.

**Markdown · Text and images** writes a `.md` file and a uniquely named adjacent `Liaoji-assets-…` folder. Keep both when moving, sharing, or uploading the document. Relative links display the actual crops. Overwriting a Markdown file creates fresh attachments and leaves older folders intact so another copy's links are not broken.

Chat text is quoted separately from document instructions. Message numbers identify positions in that export, not original WeChat message IDs. Missing dates are not invented. Excluded messages are omitted from all document exports; search filters do not limit a document export. Media Library export follows its current filters.

## Data and limits

Auto-save lives in `~/Library/Application Support/Liaoji/workspace.liaoji`. Saves are atomic; an unchanged save does not replace the previous version. Recovery preserves damaged originals. New/open actions archive the current populated project. The Organize menu opens the local data folder.

Projects include screenshots and crop coordinates, so they do not rely on original file locations. Data is local and **not encrypted**. A complete project contains private screenshots; choose a storage location accordingly.

Per-project limits are 300 screenshots, 300 MB of normalized screenshot data, 50,000 messages, and 500 media items. Each import file is limited to 30 MB. Document export limits processed image data to 80 MB and 40 million pixels; media-folder/Markdown attachment export is limited to 300 MB. Split large collections into projects.

OCR is approximate. Pictures, stickers, quoted messages, names, links, and payment cards may need manual correction. Crops are static and cannot reconstruct animated stickers, voice messages, original-resolution images, unseen conversation, or deleted content. This is not a WeChat database reader. OCR enables the five supported languages available on the current macOS version.

Projects with media require Liaoji 1.5 or newer. Earlier text-only projects remain readable. Exact overlap hints never silently delete messages.

## Checks

```sh
./scripts/swift.sh run CoreChecks
./scripts/swift.sh run ChatScribe --self-test --output /tmp/Liaoji-Checks
```

Core checks cover parsing, ordering, conservative overlap/exclusion behavior, storage recovery, undo, language coverage/placeholders, and quoted Markdown. Native integration checks generate fictional screenshots and use isolated workspaces to exercise Vision OCR, review, media, capacity limits, background export, actual DOCX/PDF images, multilingual Word documents, and Markdown attachment cleanup. Photos file promises use controlled receivers.

Use `LIAOJI_DATA_DIR` to select an isolated data directory for manual testing. Never run development tests against your real conversation workspace.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). The repository contains code and synthetic fixtures only. Projects, screenshots, backups, local validation outputs, build artifacts, and credentials are excluded from version control. Please use fictional or carefully redacted examples in issues.

MIT License.
