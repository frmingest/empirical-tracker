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

---

## Sprint 1 — Authentication, settings & app shell

All Sprint 1 Swift files are pre-written in `ios/`. Follow these steps on your Mac.

### 1. Add the `Auth` package (local)

**File > Add Package Dependencies > Add Local…** → select `Packages/Auth`

Add the `Auth` product to the **EmpiricalTracker** target.

### 2. Add `supabase-swift` (remote dependency)

The `Auth` package's `Package.swift` already declares this dependency. Xcode will
resolve it automatically the first time you open/build. If it doesn't:

**File > Add Package Dependencies** → paste `https://github.com/supabase/supabase-swift.git`
→ version: **2.0.0** or later.

> Note: `supabase-swift` is declared as a dependency of the `Auth` **package**, not
> directly of the app target. Let SPM resolve it transitively.

### 3. Drag in new source files

Drag these folders into the **EmpiricalTracker** group in Xcode (uncheck "Copy items"):

| Folder | Notes |
|---|---|
| `EmpiricalTracker/Features/Auth/` | `AuthView.swift`, `SignInViewModel.swift` |
| `EmpiricalTracker/Features/Settings/` | `AppTheme.swift`, `AppLanguage.swift`, `SettingsStore.swift`, `SettingsView.swift` |
| `EmpiricalTracker/Config/AppConfig.swift` | Reads `SupabaseURL` / `SupabaseAnonKey` from Info.plist |
| `EmpiricalTracker/Mock/MockData.swift` | Demo biomarker data |

Replace the existing `App/AppEnvironment.swift`, `App/EmpiricalTrackerApp.swift`,
and `App/RootView.swift` — they have been updated in-place.

### 4. Add Supabase credentials to Info.plist

In the **EmpiricalTracker** target → **Info** tab, add two keys:

| Key | Value |
|---|---|
| `SupabaseURL` | `https://YOUR_PROJECT_REF.supabase.co` |
| `SupabaseAnonKey` | `your-anon-key` (safe to embed — public by design) |

> **Development shortcut:** Set `DEMO_MODE=1` in the Run scheme environment variables
> to bypass Supabase entirely and use mock data. No credentials needed.

### 5. Scheme environment variables

Update **Product > Scheme > Edit Scheme > Run > Arguments > Environment Variables**:

```
EMPIRICAL_API_URL = http://localhost:8000      (or Railway URL)
DEMO_MODE        = 1                           (optional; bypasses Supabase in dev)
```

### 6. Build & run

Press **⌘R**. Expected flow:
- App opens to `AuthView` (sign-in form)
- In demo mode: tap "Try demo mode" → lands on the 5-tab shell
- In production: enter email + password → Supabase auth → 5-tab shell
- Settings tab: theme picker updates colors live; language picker shows restart notice

### Sprint 1 acceptance checklist

- [ ] Real email/password sign-in works against Supabase
- [ ] Session persists across app kills (Keychain restore on relaunch)
- [ ] Sign-out returns to `AuthView`
- [ ] Theme picker (System/Light/Dark) changes `ColorScheme` immediately
- [ ] Language picker (System/English/Norsk) shows restart notice and writes `AppleLanguages`
- [ ] Demo mode (`DEMO_MODE=1`) bypasses Supabase entirely
- [ ] `AuthStore` unit tests pass (`⌘U` in the `Auth` package)
- [ ] SwiftLint reports 0 errors
