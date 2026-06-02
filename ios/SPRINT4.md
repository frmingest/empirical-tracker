# Sprint 4 — Excel Import, Panel Timeline & Manual Data

## What This Sprint Does

Sprint 4 is the "get real data in" sprint. Before this sprint, the app could show biomarkers from the server but had no way to put data there in the first place. After this sprint, a user can tap a single button, select their lab .xlsx file, and see their blood test results on the dashboard within seconds.

---

## Feature 1 — Import a Blood Test File

### How it works from the user's perspective

1. The user taps the **download arrow icon** (↓) in the top-right corner of the Dashboard.
2. The iOS file picker opens. The user navigates to their .xlsx lab report (e.g., in Files, iCloud, email downloads) and taps it.
3. A progress ring animates while the file uploads to the server.
4. When the server finishes parsing, the app shows a **result summary**:
   - How many results were imported
   - How many panels were created
   - Any rows the server couldn't understand (shown as warnings)
5. The user taps **Done**. The dashboard refreshes automatically with the new data.

### What happens if something goes wrong

- **Wrong file format** — the server returns an error, and the app shows a red failure screen with the server's explanation. The user can tap "Try again" to pick a different file.
- **Network failure** — same failure screen, with a human-readable network error message.
- **Partial row failures** — the import still succeeds, but the result summary lists which rows were skipped and why (e.g., "Row 14: unrecognised marker 'Mg-fix'").

### Norwegian lab files

The server handles Norwegian decimal commas (1,4 instead of 1.4) and Norwegian date formats entirely. The iOS app just uploads the raw bytes — it never tries to parse the Excel file itself. This means if the server parser is updated to handle new lab formats, the iOS app works automatically without an update.

---

## Feature 2 — Open a .xlsx from Mail, Files, or AirDrop

The app is now registered as an opener for `.xlsx` files. This means:

- If someone emails a lab report to the user's iPhone, they can tap it in Mail and choose "Open in EmpiricalTracker".
- If the user receives the file via AirDrop, they can tap it and choose EmpiricalTracker.
- If they save it to Files and long-press it, EmpiricalTracker appears in the share sheet.

When the app opens this way, the import sheet appears automatically and the upload starts without the user having to tap anything extra.

**Technical note:** This works because `Info.plist` now declares `CFBundleDocumentTypes` with the `.xlsx` UTType, and the dashboard listens for `onOpenURL` to start the import flow.

---

## Feature 3 — Blood Test History (Panel Timeline)

### How it works from the user's perspective

1. The user taps the **calendar icon** in the top-left corner of the Dashboard.
2. A sheet slides up showing all their blood draws in reverse-chronological order (newest first).
3. Each card shows:
   - The date of the blood draw
   - Total number of markers tested
   - How many were in range (green)
   - How many were out of range (shown in red)
   - The actual names of the flagged markers (e.g., "LDL Cholesterol · Total Cholesterol")
4. The user can pull-to-refresh to fetch any newly imported panels.

### Deleting a single panel

- Swipe left on a panel card and tap the red **Delete** button.
- A confirmation dialog appears: "This will permanently remove the [date] panel and all its results. This cannot be undone."
- The user taps **Delete** to confirm or **Cancel** to go back.
- The panel disappears from the list immediately.

### Deleting everything

- Tap the **⋯** menu in the top-right corner of the history screen.
- Tap **Delete all panels**.
- A confirmation dialog appears listing how many panels will be deleted.
- After confirmation, all panels and all biomarker results are cleared. The dashboard returns to its empty state.

---

## Technical Architecture

### New Files

| File | What it does |
|------|-------------|
| `Packages/Core/.../ImportModels.swift` | The data shape the server sends back after a successful import (panel ID, counts, error list). |
| `Packages/Biomarkers/.../BiomarkersImportService.swift` | Handles the file upload. Builds a multipart/form-data HTTP request and sends the raw .xlsx bytes to `POST /biomarkers/import`. Reports upload progress (0→100%). |
| `Features/Import/ImportViewModel.swift` | Manages the state of the import sheet: idle → uploading → success or failure. |
| `Features/Import/ImportSheetView.swift` | The full-screen sheet the user sees. Shows the file picker button, progress ring, result summary, or error screen depending on the state. |
| `Features/Panels/PanelTimelineViewModel.swift` | Loads panels from the server, figures out which markers were flagged on each draw date, and handles delete logic. |
| `Features/Panels/PanelTimelineView.swift` | The history screen. A scrollable list with swipe-to-delete and a "Delete all" menu. |
| `Features/Panels/PanelCardView.swift` | A single card in the history list. |
| `EmpiricalTracker/Info.plist` | App metadata including the `.xlsx` document type registration so the app appears in iOS share sheets. |

### Modified Files

| File | What changed |
|------|-------------|
| `BiomarkersRepository.swift` | Added `importXLSX()` — orchestrates the upload, then refreshes both panels and results so the dashboard updates automatically. |
| `AppEnvironment.swift` | Creates and owns a `BiomarkersImportService` instance so all screens can access the import capability. |
| `DashboardView.swift` | Wired the import toolbar button (previously a TODO), added the history toolbar button, and added `onOpenURL` to handle files opened from other apps. |
| `project.pbxproj` | Switched the main target from auto-generated Info.plist to the explicit `Info.plist` file. |

### Why multipart upload instead of JSON?

The existing `APIClient` encodes all request bodies as JSON. An Excel file is binary data, not JSON. Rather than redesign the shared client (which would affect every other feature), Sprint 4 introduces a separate `BiomarkersImportService` that constructs its own `URLRequest` with a `multipart/form-data` body. It still borrows the auth token and base URL from the same configuration, so it behaves consistently with the rest of the app.

### Why are flagged marker names computed client-side?

The `Panel` model returned by `GET /biomarkers/panels` includes counts (total, in-range, out-of-range) but not the names of flagged markers. Rather than add a new API endpoint for Sprint 4, the app cross-references the panel's draw date with the biomarker results already in memory. If a marker has a measurement on that exact calendar day with `inRange = false`, it's added to the "flagged" list. This adds zero network requests.

---

## Acceptance Criteria Checklist

- [x] A real Norwegian .xlsx imports end-to-end on device (decimal commas, dates handled server-side)
- [x] Import progress is shown during upload
- [x] Result summary (panels created / results inserted) shown after success
- [x] Errors surfaced clearly (wrong format, row-level warnings)
- [x] Import success triggers dashboard refresh automatically
- [x] Files / AirDrop / share-sheet entry point works (.xlsx opens the app and starts import)
- [x] Panel timeline shows draws in chronological order with per-panel summary
- [x] Flagged marker names are listed on each panel card
- [x] Delete a single panel with confirmation dialog
- [x] Delete all panels with confirmation dialog
- [x] Both delete operations are undo-safe (confirmation required before any data is removed)
