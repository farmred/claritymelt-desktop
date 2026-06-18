# ClarityMelt Desktop (Flutter macOS)

A native macOS desktop application for ClarityMelt — infrastructure management with clear connections between machines, domains, and DNS records. Org-scoped encrypted credentials stored locally in SQLite.

## Architecture

This is a **self-contained desktop application** — no separate API server needed. The app directly calls provider APIs (OVH, Hetzner, Namecheap, Cloudflare) and stores all data locally in SQLite.

### Key Differences from the Web App

| Feature | Web App | Desktop App |
|---------|---------|-------------|
| Backend | Hono + tRPC + PostgreSQL | Direct API calls + SQLite |
| Auth | Better Auth (multi-user) | Single-user (no auth) |
| Database | PostgreSQL (remote) | SQLite (local) |
| Credentials | Encrypted in DB, env var fallback | Encrypted in local DB, env var fallback |
| State Management | Preact signals | Riverpod |
| UI | Preact + Tailwind | Flutter Material 3 |

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

The built app will be at `build/macos/Build/Products/Release/claritymelt_desktop.app`.

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
- https://github.com/LollipopKit/flutter_server_box
- https://github.com/TerminalStudio
- https://pub.dev/packages/dartssh2
- https://github.com/TerminalStudio/xterm.dart
