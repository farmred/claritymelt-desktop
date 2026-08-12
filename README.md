# ClarityMelt Desktop (Flutter macOS)

A native macOS desktop application for ClarityMelt — infrastructure management with clear connections between machines, domains, and DNS records. Encrypted credentials stored locally in SQLite.

## Architecture

This is a **self-contained desktop application** — no separate API server needed. The app directly calls provider APIs (OVH, Hetzner, Namecheap, Cloudflare) and stores all data locally in SQLite.

### Project Structure

```
lib/
├── database/           # Drift (SQLite) database layer
│   ├── database.dart   # AppDatabase with all tables
│   ├── tables.dart     # Table definitions
│   └── daos/           # Data access objects
├── models/             # Data models (MachineInfo, DomainInfo, etc.)
├── services/           # External service clients
│   ├── cloudflare_service.dart   # Cloudflare API
│   ├── hetzner_service.dart      # Hetzner API
│   ├── namecheap_service.dart    # Namecheap API
│   ├── ovh_service.dart          # OVH API
│   ├── crypto_service.dart       # AES-256 encryption
│   └── infrastructure_service.dart  # Orchestrator + caching
├── providers/          # Riverpod state providers
│   └── app_providers.dart
├── screens/            # UI screens
│   ├── machines_screen.dart
│   ├── domains_screen.dart
│   ├── dns_manager_screen.dart
│   └── providers_screen.dart
├── theme/              # App theme
│   └── app_theme.dart
└── main.dart           # App entry point
```

## Setup

### Prerequisites

- Flutter SDK 3.22+
- macOS development tools (Xcode)

### Install Dependencies

```bash
cd claritymelt_desktop
flutter pub get
dart run build_runner build  # Generate Drift database code
```

### Run in Development

```bash
flutter run -d macos
```

### Build Release

```bash
flutter build macos
```

The built app will be at `build/macos/Build/Products/Release/ClarityMelt.app`.

## Mac App Store Distribution

### Packaging

The `tool/package.sh` script handles building, archiving, and packaging:

```bash
# Check setup (Xcode, Flutter, signing certs)
make check

# Build release .app
make build

# Create DMG for direct distribution
make dmg

# Archive for App Store submission
make archive

# Generate App Store metadata
make metadata

# Full pipeline (build + DMG + metadata)
make package
```

### App Store Submission

1. **Build & archive**: `make archive`
2. Open **Xcode → Organizer**, select the archive
3. Click **Distribute App** → **Mac App Store**
4. Upload to **App Store Connect**
5. Add metadata (description, keywords, screenshots)
6. Submit for review

### Direct Distribution (DMG)

```bash
# Build DMG
make dmg

# Notarize (requires Apple Developer account)
export APPLE_ID_EMAIL=your@email.com
export APPLE_ID_PASSWORD=app-specific-password
export DEVELOPMENT_TEAM=YOUR_TEAM_ID
make notarize
```

### Notarization

macOS apps distributed outside the App Store must be notarized:

1. Archive your app with a Developer ID certificate
2. Submit to Apple's notarization service: `make notarize`
3. Staple the ticket: done automatically by the notarize script

### Configuration

| Setting | File | Value |
|---------|------|-------|
| Bundle ID | `macos/Runner/Configs/AppInfo.xcconfig` | `com.claritymelt.app` |
| App Name | `macos/Runner/Configs/AppInfo.xcconfig` | `ClarityMelt` |
| Version | `pubspec.yaml` | `1.0.0+1` |
| Entitlements | `macos/Runner/Release.entitlements` | sandbox + network |
| Team ID | Env var `DEVELOPMENT_TEAM` | Your Apple Team ID |

## Environment Variables (Optional Fallback)

Provider credentials can be configured per-organization in the UI (recommended), or via environment variables as a fallback:

```bash
# OVH Cloud
export OVH_APPLICATION_KEY=""
export OVH_APPLICATION_SECRET=""
export OVH_CONSUMER_KEY=""

# Hetzner Cloud
export HETZNER_API_TOKEN=""

# Namecheap
export NAMECHEAP_API_USER=""
export NAMECHEAP_API_KEY=""
export NAMECHEAP_CLIENT_IP=""

# Cloudflare
export CLOUDFLARE_API_TOKEN=""
export CLOUDFLARE_ACCOUNT_ID=""
```

To pass environment variables when running:

```bash
flutter run -d macos --dart-define=HETZNER_API_TOKEN=your_token
```

## Features

- **Machines**: View VPS instances from OVH and Hetzner, linked to DNS records
- **Domains**: View domains from Cloudflare, Namecheap, and OVH with DNS zone info
- **DNS Records**: Manage Cloudflare DNS records (CRUD operations)
- **Providers**: Add/remove org-scoped API credentials (encrypted with AES-256)
- **Domain Provisioning**: Create Cloudflare zone + A record + update nameservers in one step
- **Offline Cache**: Data is cached in SQLite for fast local reads; "Sync Live" refreshes from APIs
- **Credential Encryption**: All stored credentials are AES-256 encrypted before writing to SQLite

## Database Schema (SQLite)

- `provider_credentials` — Encrypted API credentials per organization
- `cached_machines` — Cached VPS instance data
- `cached_domains` — Cached domain data
- `cached_dns_records` — Cached DNS record data
- `preferences` — Key-value app settings (encryption key, theme, org name)

## App Store Screenshots

Generate screenshots at standard macOS App Store distribution sizes:

| Size | Use Case |
|------|----------|
| 1280 × 800 | MacBook Air 13" (non-Retina) |
| 1440 × 900 | MacBook Air 13" (scaled) / 15" (non-Retina) |
| 2560 × 1600 | MacBook Air/Pro 13" (Retina @2×) |
| 2880 × 1800 | MacBook Pro 15/16" (Retina @2×) |

### Automated (Integration Test)

```bash
make screenshots
# or: ./tool/screenshot.sh auto
```

### Interactive (Manual Window Capture)

```bash
# 1. Start the app
flutter run -d macos

# 2. Run manual capture (resizes window + screencapture per tab)
make screenshots-manual
# or: ./tool/screenshot.sh manual
```

### Quick Capture (Active Window)

```bash
flutter run -d macos
make screenshots-quick
# or: ./tool/screenshot.sh quick
```

Screenshots are saved to `screenshots/{size}/` with naming: `{tab}_{size}.png`.

## Tech Stack

- **Flutter** — Cross-platform UI framework
- **Drift** — Type-safe SQLite database (formerly Moor)
- **Riverpod** — Reactive state management
- **window_manager** — macOS window configuration
- **encrypt** — AES-256 credential encryption
- **http** — HTTP client for provider APIs
- **crypto** — HMAC-SHA1 (OVH request signing)


Other design ideas
- https://www.designdotmd.directory/d/neon-arcade
- https://www.designdotmd.directory/d/jrpg-menu
- https://www.designdotmd.directory/d/candy-tap


Ssh related
- https://pub.dev/packages/dartssh2
- https://github.com/TerminalStudio/xterm.dart
