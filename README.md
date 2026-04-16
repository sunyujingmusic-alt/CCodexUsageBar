# CCodexUsageBar

A minimal macOS menu bar app that shows your **remaining CCodex daily quota**.

It is designed for one very specific job:

- read today's usage from `https://ccodex.net/usage`
- calculate the remaining daily quota
- keep that number available from the macOS menu bar

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

## Target page

- Dashboard usage page: `https://ccodex.net/usage`

## Important visible numbers on the page

The dashboard presents several stats, but the critical one is:

- **总消费** (the large displayed total cost)

That value is the one most useful for day-to-day quota decisions.

## Actual backend endpoints used by the page

### 1. Usage stats

```http
GET /api/v1/usage/stats?start_date=YYYY-MM-DD&end_date=YYYY-MM-DD&timezone=Asia/Shanghai
```

Important fields:

- `data.total_actual_cost` → the large displayed cost on the page
- `data.total_cost` → standard cost
- `data.total_requests`
- `data.total_input_tokens`
- `data.total_output_tokens`
- `data.total_cache_tokens`
- `data.average_duration_ms`

### 2. Active subscription

```http
GET /api/v1/subscriptions/active?timezone=Asia/Shanghai
```

Important fields:

- `data[0].group.daily_limit_usd` → daily limit
- `data[0].daily_usage_usd` → backend daily usage field
- `data[0].group.name` → subscription/group name
- `data[0].group.rate_multiplier` → rate multiplier

---

## Which number should be treated as the real "used today" number?

This project intentionally uses:

```json
usage.stats.data.total_actual_cost
```

Reason:

- it is the number the dashboard emphasizes visually
- it matches the mental model of "how much have I actually spent today?"
- it is the most useful value for menu-bar level decision support

### Why not use `daily_usage_usd` as the primary number?

Observed behavior showed:

- `daily_usage_usd` is often closer to `total_cost`
- the large dashboard number is `total_actual_cost`
- when a multiplier is in play, `total_actual_cost` can differ significantly from `daily_usage_usd`

So for user-facing quota awareness, this app treats:

- `total_actual_cost` as the primary "used" value
- `daily_limit_usd` as the hard cap
- `remaining = daily_limit_usd - total_actual_cost`

---

# Authentication Research

## The site is token-based, not cookie-based

The dashboard session is not primarily maintained through browser cookies.

Relevant browser-side storage includes:

- `localStorage.auth_token`
- `localStorage.refresh_token`
- `localStorage.auth_user`

That means the correct architecture for a native app is:

- log in with account credentials
- obtain `access_token` and `refresh_token`
- store them locally
- refresh automatically when needed

## Official auth endpoints

### Login

```http
POST /api/v1/auth/login
```

Request body:

```json
{
  "email": "...",
  "password": "..."
}
```

### Refresh token

```http
POST /api/v1/auth/refresh
```

Request body:

```json
{
  "refresh_token": "..."
}
```

### Expected auth flow

1. user logs in with email + password
2. app receives:
   - `access_token`
   - `refresh_token`
   - `expires_in`
3. app stores them locally
4. usage requests use:

```http
Authorization: Bearer <access_token>
```

5. on token expiry / 401:
   - call `/auth/refresh`
   - update tokens
   - retry usage fetch

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
- saving tokens after successful login
- checking whether the current access token is still usable
- refreshing tokens when necessary
- optionally reusing saved credentials when refresh fails

### `CCodexAPI.swift`

Responsible for:

- calling `/api/v1/auth/login`
- calling `/api/v1/auth/refresh`
- calling `/api/v1/usage/stats`
- calling `/api/v1/subscriptions/active`
- assembling the final `QuotaSnapshot`

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
- token expiry timestamp
- remember-password preference

### `KeychainTokenStore.swift`

Historical name retained in code, but the current implementation uses a local app-specific credential file for runtime convenience during development.

It stores:

- access token
- refresh token
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
- access token + refresh token storage
- automatic token refresh
- optional saved password for silent relogin if refresh fails

## Why save password optionally?

There are two possible user experience levels:

### More secure

- store only refresh token
- ask for password again if refresh becomes invalid

### More hands-off

- also store email/password locally
- re-login automatically if refresh fails

This project currently supports the second option because the original goal favored low-friction personal use.

---

# Refresh Strategy

## Refresh cadence

The app refreshes:

- once at launch
- periodically on a timer
- manually when the user chooses refresh from the menu

## Error states

If refresh fails, the app can show:

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
```

The current script builds:

1. `arm64-apple-macos12.0`
2. `x86_64-apple-macos12.0`
3. combines them with `lipo`

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

The app is now built for both Apple Silicon and Intel Macs.

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
