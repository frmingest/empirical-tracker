# Legal documents — status

Source text for the app's legal documents lives here:

- [`privacy-policy.md`](./privacy-policy.md)
- [`terms-of-service.md`](./terms-of-service.md)

## Status: ⚠️ DRAFTED — not yet hostable

The documents are written but **cannot be linked from the app or App Store
Connect yet**. Two things are outstanding.

### 1. Decide on a hosting domain / public URLs — **OPEN**

The app links to the privacy policy and terms, and App Store Connect requires a
publicly reachable privacy-policy URL. We have **not** chosen where these will be
hosted. The code currently uses **placeholder** URLs on the `empirical.app`
domain, which is not confirmed as ours.

- Referenced in code: `ios/EmpiricalTracker/Config/Legal.swift`
  (`privacyPolicyURL`, `termsOfServiceURL`).
- In-app surfaces that use them: the auth screen footer, the **Legal** section in
  **Settings**, and the health-data **consent** screen.

**To resolve:** pick the domain / hosting (e.g. a GitHub Pages site, the marketing
site, or a docs host), publish these two documents there, then update the two
URLs in `Legal.swift` and paste the privacy-policy URL into App Store Connect ▸
App Privacy.

### 2. Fill in the `[TBD: …]` placeholders — **OPEN**

Both documents contain `[TBD: …]` markers that need real values before
publishing, and the text should get a legal review. Outstanding items:

- Data controller's legal name and postal address.
- Privacy / legal contact email.
- Effective ("Last updated") date.
- Minimum age.
- Governing-law jurisdiction (Terms).
- Confirm sub-processor regions (Railway, Withings).

Until both items are closed, treat the in-app links as **placeholders**.
