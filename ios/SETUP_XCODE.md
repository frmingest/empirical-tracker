# iOS Sprint 0 — Xcode Setup Guide

All Swift source files, Swift packages, asset catalogs, and the string catalog
are ready. Follow these steps on a Mac with Xcode 16+ installed.

---

## 1. Prerequisites

- Xcode 16 or later (for Swift 6 + iOS 17 APIs)
- An Apple Developer account (free or paid — paid required for device signing)
- SwiftLint installed: `brew install swiftlint`

---

## 2. Create the Xcode project

1. Open Xcode → **File > New > Project**
2. Choose **iOS > App**
3. Fill in:
   - **Product Name:** `EmpiricalTracker`
   - **Bundle Identifier:** `com.empirical.tracker` *(change to your own prefix)*
   - **Interface:** SwiftUI
   - **Language:** Swift
   - **Include Tests:** ✓
4. Save the project **inside** the `ios/` folder next to `EmpiricalTracker/` and `Packages/`

Your layout should look like:
```
ios/
├── EmpiricalTracker.xcodeproj/   ← created by Xcode
├── EmpiricalTracker/             ← source files (already written)
├── Packages/                     ← Swift packages (already written)
└── .swiftlint.yml
```

---

## 3. Replace the generated source files

Xcode creates placeholder `ContentView.swift` and `[AppName]App.swift` files.
Delete them and drag the pre-written files in:

1. In the Xcode Project Navigator, delete Xcode's generated files (Move to Trash).
2. Drag the entire `EmpiricalTracker/App/` folder into the **EmpiricalTracker** target.
   - ✓ "Copy items if needed" → **uncheck** (files are already in place)
   - ✓ "Add to targets" → **EmpiricalTracker**

---

## 4. Add the Assets & String Catalog

1. Delete Xcode's generated `Assets.xcassets`.
2. Drag `EmpiricalTracker/Assets.xcassets` into the project — it contains all 12
   semantic colors (light + dark) mirroring the CSS custom properties.
3. Drag `EmpiricalTracker/Localizable.xcstrings` into the project root.

---

## 5. Add the Swift Packages (local)

Add each feature package via **File > Add Package Dependencies > Add Local…**

Add in this order (Core first, since others depend on it):

| Package folder | Product to add |
|---|---|
| `Packages/Core` | `Core` |
| `Packages/Biomarkers` | `Biomarkers` |
| `Packages/DietEvents` | `DietEvents` |
| `Packages/FoodDiary` | `FoodDiary` |
| `Packages/BodyMetrics` | `BodyMetrics` |
| `Packages/HealthSync` | `HealthSync` |
| `Packages/Account` | `Account` |

Link all products to the **EmpiricalTracker** target.

---

## 6. App Capabilities

In the **EmpiricalTracker** target → **Signing & Capabilities**:

- Add **HealthKit** (reserved now; used in Sprint 9)
- Add **App Groups** if you plan to share data with a widget extension later

---

## 7. Scheme environment variable

Set `EMPIRICAL_API_URL` in the Run scheme to point at your local or Railway backend:

**Product > Scheme > Edit Scheme > Run > Arguments > Environment Variables:**

```
EMPIRICAL_API_URL = http://localhost:8000
```

For production use the Railway URL. The `APIClient.Configuration.resolved()` method
reads this variable at runtime.

---

## 8. Build & run

1. Select the `EmpiricalTracker` scheme and an iOS 17+ simulator.
2. Press **⌘R**.
3. The app should launch to the placeholder auth screen with "Sign in (demo)" button.
4. Tap it → you land on the five-tab skeleton.

**Expected build result:** 0 errors, 0 warnings (SwiftLint may flag a few disabled-rules
if you haven't installed it yet — that's fine for Sprint 0).

---

## 9. Run the contract tests

The `Core` package includes `DTOContractTests` which validate every Codable DTO against
fixture JSON matching the live backend response shapes.

```
Product > Test  (⌘U)
```

All tests should pass without a running backend.

---

## 10. SwiftLint integration

Add a Run Script build phase **before** Compile Sources:

```bash
if which swiftlint > /dev/null; then
  swiftlint --config "${SRCROOT}/../.swiftlint.yml"
fi
```

---

## Sprint 0 acceptance checklist

- [ ] App builds in simulator
- [ ] Placeholder TabView renders with 5 tabs
- [ ] "Sign in (demo)" button transitions to the tab shell
- [ ] `⌘U` — all `DTOContractTests` pass
- [ ] SwiftLint reports 0 errors
- [ ] Color assets switch correctly between light and dark mode
- [ ] `EMPIRICAL_API_URL` env var is wired in the scheme

---

## Sprint 1 next steps

- Add `supabase-swift` via Swift Package Manager (remote package)
- Implement `SupabaseTokenProvider: TokenProvider`
- Wire real email/password auth in `AuthView`
- Store JWT in Keychain via `SecItem` APIs
- Implement `AuthStore` (`@Observable`) with session restore + 401 re-auth flow
