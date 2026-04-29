# CCodexUsageBar

A minimal macOS menu bar app that shows your **remaining CCodex daily quota**.

It is designed for one very specific job:

- log into the current `https://ccodex.net` console
- read the current quota / usage data from the New API endpoints the site now uses
- keep the most useful remaining amount available from the macOS menu bar

The UI is intentionally small and quiet.

---

## What the app shows

The app is built around one decision-making number:

```text
remaining = daily_limit_usd - total_actual_cost
```

Typical menu bar states:

- `余 $165.73` — normal
- `超 $12.40` — over limit
- `额度 --` — not logged in / failed to refresh
- `同步中…` — currently refreshing

When opened from the menu bar, it also shows:

- today's consumed amount
- daily limit
- today's remaining quota
- group / subscription name
- last update time
- refresh / login / settings / logout actions

---

## Why this project exists

The original problem was simple:

> "I want to see today's already-consumed CCodex amount quickly, so I can decide how aggressively to keep using it for the rest of the day."

The web dashboard already exposes the number, but opening the page repeatedly is slower than glancing at the menu bar.

So this project extracts the dashboard's key usage number and turns it into a native macOS utility.

---

# Research Summary

## Current site shape

CCodex has moved away from the old `/usage` + `/api/v1/...` stack.

The useful console pages are now under:

- `https://ccodex.net/login`
- `https://ccodex.net/console`
- `https://ccodex.net/console/log`
- `https://ccodex.net/console/token`

The old endpoints such as `/api/v1/usage/stats` and `/api/v1/subscriptions/active` are no longer the right basis for the app.

## Backend endpoints currently used by this app

The menu bar app now works from the site’s newer API surface:

```http
POST /api/user/login
GET  /api/user/self
GET  /api/status
GET  /api/log/self/stat
GET  /api/subscription/self
```

Important fields:

- `/api/user/login` → establishes the authenticated session cookie and returns the current user id
- `/api/user/self` → validates the current session and provides the group / fallback quota fields
- `/api/status` → provides `quota_per_unit`, currency display settings, and exchange metadata
- `/api/log/self/stat` → provides the current log/quota aggregate used for the main “已消费” value
- `/api/subscription/self` → provides total/used subscription quota used for limit + remaining display

## Authentication model

The current site is **not** driven by a reusable bearer access token in this app.

The working native flow is:

1. `POST /api/user/login` with:

```json
{
  "username": "email-or-username",
  "password": "..."
}
```

2. the server returns basic user data including the user id
3. the server also sets a `session` cookie
4. subsequent authenticated requests must include both:
   - the session cookie
   - `New-API-User: <user id>`

In other words: **cookie-backed session + `New-API-User` header** is the key combination.

## Data model used in the menu bar

The app currently displays:

- consumed amount → primarily from `/api/log/self/stat`
- limit / remaining → from `/api/subscription/self`
- currency symbol / quota conversion → from `/api/status`
- group name → from `/api/user/self`

When `quota_per_unit` is present, the app converts raw quota to display currency before rendering the menu.

---

## Why browser-token scraping is not the main solution

An earlier approach attempted to import the token from a live browser session.

That path relied on:

- AppleScript automation
- browser-specific scripting permissions
- page-context access to `localStorage`

It worked as a research technique, but it proved too brittle as the primary product path.

So the project moved to:

- **native in-app login** as the primary path
- browser token import retained only as historical research / optional future tooling

---

# Product / UX Goals

## Primary goal

Keep quota awareness frictionless.

The desired experience is:

1. user logs in once
2. app stays in the menu bar
3. app refreshes automatically
4. user checks remaining quota with a glance

## UI constraints

- very small footprint
- menu bar first
- no heavy dashboard UI
- no browser dependency in normal use
- simple login window only when needed

---

# Architecture

## Platform choice

The app uses **AppKit + SwiftUI** rather than a pure SwiftUI `MenuBarExtra` design.

Reason:

- better compatibility with **macOS 12–15**
- more predictable status-item behavior
- simpler control over a classic menu bar utility

## Core stack

- **AppKit** for `NSStatusBar` / `NSStatusItem`
- **NSMenu** for the dropdown menu
- **SwiftUI** for small windows (login / settings)
- **URLSession** for API requests
- **UserDefaults** for basic settings
- **local credential store** for tokens / saved login state

---

## Main modules

### `main.swift`

Starts the app as a menu-bar utility.

### `AppDelegate.swift`

Application entry point that wires up the main controllers.

### `StatusBarController.swift`

Responsible for:

- creating the menu bar item
- rendering title states
- scheduling refreshes
- updating visible usage values
- opening login/settings windows
- handling logout and retry flows

### `AuthManager.swift`

Responsible for:

- native login with email/password
- persisting the logged-in user id for `New-API-User`
- validating whether the current cookie-backed session is still usable
- optionally reusing saved credentials when the session expires
- clearing session cookies and local login state on logout

### `CCodexAPI.swift`

Responsible for:

- calling `/api/user/login`
- calling `/api/user/self`
- calling `/api/status`
- calling `/api/log/self/stat`
- calling `/api/subscription/self`
- assembling the final `QuotaSnapshot`
- reusing the same `URLSession` so the login cookie survives follow-up requests

### `LoginWindowController.swift`

Small login window that collects:

- email
- password
- optional "remember password" preference

### `PreferencesWindowController.swift`

Small settings window for:

- base URL
- timezone
- refresh interval

### `PreferencesStore.swift`

Stores user preferences such as:

- base URL
- timezone
- refresh interval
- remember-password preference
- logged-in user id

### `KeychainTokenStore.swift`

Historical name retained in code, but the current implementation uses a local app-specific credential file for runtime convenience during development.

It stores:

- email
- password (optional)

---

# Data Model

## `QuotaSnapshot`

```swift
struct QuotaSnapshot {
    let dateString: String
    let totalActualCost: Double
    let totalStandardCost: Double
    let backendDailyUsageUSD: Double?
    let dailyLimitUSD: Double?
    let remainingUSD: Double?
    let groupName: String?
    let rateMultiplier: Double?
    let fetchedAt: Date
}
```

This model is what the menu bar ultimately renders.

---

# Login and Session Strategy

## Current strategy

The current implementation uses:

- native login inside the app
- a cookie-backed session maintained by one shared `URLSession`
- stored user id for the `New-API-User` request header
- optional saved password for silent relogin if the session expires

## Why save password optionally?

There are two possible user experience levels:

### More secure

- store only the cookie-backed session state in memory
- ask for password again when the session expires

### More hands-off

- also store email/password locally
- re-login automatically when the session expires

This project currently supports the second option because the original goal favored low-friction personal use.

---

# Refresh Strategy

## Refresh cadence

The app refreshes:

- once at launch
- periodically on a timer
- manually when the user chooses refresh from the menu

## Error states

If session validation or re-login fails, the app can show:

- `额度 --`
- login prompt
- synced values cleared from the visible UI

This keeps the failure mode obvious without turning the app into a noisy alert system.

---

# Compatibility

## Supported macOS versions

- macOS 12
- macOS 13
- macOS 14
- macOS 15

## Universal build

The project now builds as **Universal 2**:

- `arm64`
- `x86_64`

This is important because an earlier build only produced `arm64`, which could not run on Intel Macs and appeared in Finder as a forbidden / unsupported app.

That issue is now fixed in the build script.

---

# Build

## Quick build

```bash
cd apps/CCodexUsageBar
bash build.sh
```

Output:

```text
build/CCodexUsageBar.app
build/CCodexUsageBar-universal.zip
```

The current script now does one thing by default:

1. build `arm64-apple-macos12.0`
2. build `x86_64-apple-macos12.0`
3. combine them into one Universal 2 app with `lipo`
4. verify the final bundle contains both `arm64` and `x86_64`
5. verify `CFBundleExecutable` and `LSMinimumSystemVersion`
6. package that single app as `CCodexUsageBar-universal.zip`
7. clear the old build directory first, so stale per-arch outputs do not remain

### Validation commands

After building, you can double-check the result with:

```bash
file build/CCodexUsageBar.app/Contents/MacOS/CCodexUsageBar
lipo -info build/CCodexUsageBar.app/Contents/MacOS/CCodexUsageBar
```

Expected result:

- app binary is a **Mach-O universal binary**
- architectures include **`arm64`** and **`x86_64`**
- minimum supported macOS stays **12.0**

## Optional XcodeGen workflow

The repo also includes `project.yml`.

If you prefer an Xcode project:

```bash
xcodegen generate
```

---

# Run

```bash
open build/CCodexUsageBar.app
```

On first launch, if no valid session is available, the app opens a login window.

---

# Directory Structure

```text
CCodexUsageBar/
├── README.md
├── .gitignore
├── build.sh
├── project.yml
├── Resources/
│   └── Info.plist
└── Sources/
    ├── AppDelegate.swift
    ├── AuthManager.swift
    ├── BrowserTokenReader.swift
    ├── CCodexAPI.swift
    ├── KeychainTokenStore.swift
    ├── LoginWindowController.swift
    ├── Models.swift
    ├── PreferencesStore.swift
    ├── PreferencesWindowController.swift
    ├── StatusBarController.swift
    └── main.swift
```

---

# Notable Engineering Iterations

## 1. Browser token import experiment

Implemented and tested, but not chosen as the main UX because it was too dependent on browser automation behavior.

## 2. Native login path

Implemented as the main path because it matches the site's real auth architecture.

## 3. Crash fix

An earlier build crashed due to a Swift concurrency issue around async request orchestration.

That was fixed by simplifying refresh/fetch behavior and removing the problematic async pattern.

## 4. Storage simplification

During development, storing credentials through the local app-controlled file path proved more practical than relying on unsigned-app Keychain flows that could trigger system authorization interruptions.

## 5. Universal 2 packaging

The app is now distributed as a single Universal 2 build for both Apple Silicon and Intel Macs.

---

# Security Notes

## Current state

This repository is for a practical personal utility app, not a hardened enterprise product.

The current implementation prioritizes:

- smooth native login
- reliable automatic refresh
- low-friction daily use

## If you want to harden it later

Recommended future improvements:

- code signing
- notarization
- move credential storage back to Keychain once signing/distribution is stable
- optional launch-at-login support
- optional low-quota notifications

---

# Future Improvements

Possible next steps:

- launch at login
- configurable warning thresholds
- richer menu bar title modes (`used`, `remaining`, `used / limit`)
- signed distribution builds
- notarized releases
- optional charts/history view
- proper 2FA/TOTP fallback flow if the server enables it later
- optional WebView fallback login if auth policy becomes stricter

---

# Repository Scope

This repository contains only the standalone app project.

It does **not** include the broader personal workspace used during development.

That separation is deliberate:

- keeps the public repo focused
- avoids leaking unrelated private files
- makes the app easier to clone, inspect, and build independently

---

# License / Usage

No explicit license file has been added yet.

Until a license is added, treat the repository as source-visible but not automatically open for unrestricted reuse.

If this project is meant to become fully open source, adding a license should be one of the next housekeeping steps.
