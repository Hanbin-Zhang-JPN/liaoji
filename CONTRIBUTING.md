# Contributing

Liaoji is a Swift Package with a small native macOS app and a Foundation-only core. Keep the two-column interface simple and preserve the original conversation data.

## Layout

- `Sources/ChatCore`: project models, ordering, parsing, history, local storage, transcript metadata, Markdown text, and localization.
- `Sources/ChatScribe`: SwiftUI/AppKit interface, local Vision OCR, media crops, background export, Word/PDF/Markdown packaging, and isolated native integration checks.
- `Tests/CoreChecks`: executable core checks.
- `scripts`: command-line build helpers and application packaging.

Run `./scripts/swift.sh run CoreChecks` after relevant core changes. Run `./scripts/swift.sh run ChatScribe --self-test --output /tmp/Liaoji-Checks` for native changes; those checks need normal macOS OCR/clipboard services. Build the actual app with `./scripts/build-app.sh` to verify bundled translation resources.

## Languages

`Sources/ChatCore/Resources/Translations.json` maps source keys to `zh-Hans`, `zh-Hant`, `ja`, `en`, and `ko`. Keep placeholder sets identical in every translation. Call `L10n.text` for application strings, never on user-authored chat text. Use `L10n.display` only for application-generated status or error strings. Background exports capture a task-local language without changing the interface preference.

Check each affected interface language in an isolated workspace. Menus, dialogs, search, long labels, and live language switching must remain usable. Preserve participant names, notes, message text, screenshot pixels, and stored review state.

## Export and storage changes

Keep exports local and deterministic. Preserve message order, source context, explicit time labels, review status, and exclusions. Chat content is data, not executable instructions. Do not invent missing dates or interpret pictures automatically.

Check actual image entries in Word/PDF files and open rendered pages after layout changes. Markdown must use valid relative image links. Write files atomically and remove only attachment directories created by the failed operation; never remove older user folders as cleanup.

Storage changes need backward-compatible reads or a deliberate format version with protected recovery. Test undo/redo and failure cases as well as the successful path.

## Private data

Do not commit `.liaoji` files, screenshots, backups, validation directories, exported conversations, credentials, or diagnostic logs containing real chat text. Tests generate fictional data and use temporary workspaces. Issue reports should use fictional or redacted reproductions.
