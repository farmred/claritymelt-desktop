#!/usr/bin/env bash
set -euo pipefail

# ────────────────────────────────────────────────────────────────────────
# ClarityMelt — macOS App Store Package Builder
#
# Builds, archives, and exports the app for Mac App Store distribution.
# Also generates a DMG for direct distribution / notarization.
#
# Prerequisites:
#   - Xcode with command-line tools installed
#   - Apple Developer account with certificates installed
#   - Valid provisioning profiles for com.claritymelt.app
#
# Usage:
#   ./tool/package.sh                # Full build + archive + export
#   ./tool/package.sh build          # Build release only
#   ./tool/package.sh archive       # Archive for App Store
#   ./tool/package.sh dmg            # Create DMG for direct distribution
#   ./tool/package.sh screenshots    # Generate screenshots
#   ./tool/package.sh all            # Build + archive + DMG + screenshots
#   ./tool/package.sh check          # Validate setup (certs, profiles)
# ────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${PROJECT_DIR}/build"
RELEASE_APP="${BUILD_DIR}/macos/Build/Products/Release/ClarityMelt.app"
ARCHIVE_PATH="${BUILD_DIR}/macos/ClarityMelt.xcarchive"
EXPORT_DIR="${BUILD_DIR}/macos/Export"
DMG_DIR="${BUILD_DIR}/macos/Distribution"
SCREENSHOTS_DIR="${PROJECT_DIR}/screenshots"

# ── Configuration ──────────────────────────────────────────────────────
BUNDLE_ID="com.claritymelt.app"
APP_NAME="ClarityMelt"
TEAM_ID="${DEVELOPMENT_TEAM:-}"   # Set via env var or Xcode
VERSION="$(grep 'version:' "${PROJECT_DIR}/pubspec.yaml" | head -1 | sed 's/version: //;s/+.*//;s/ //g')"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${CYAN}ℹ️  $1${NC}"; }
ok()    { echo -e "${GREEN}✅ $1${NC}"; }
warn()  { echo -e "${YELLOW}⚠️  $1${NC}"; }
err()   { echo -e "${RED}❌ $1${NC}"; }

# ── Pre-flight checks ──────────────────────────────────────────────────
check_setup() {
  echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║     ClarityMelt — Package Setup Check                   ║${NC}"
  echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
  echo ""

  # Xcode
  if xcode-select -p &>/dev/null; then
    XCODE_VER="$(xcodebuild -version | head -1)"
    ok "Xcode: $XCODE_VER"
  else
    err "Xcode not found. Install from https://developer.apple.com/xcode/"
    return 1
  fi

  # Flutter
  if command -v flutter &>/dev/null; then
    FLUTTER_VER="$(flutter --version 2>&1 | head -1)"
    ok "Flutter: $FLUTTER_VER"
  else
    err "Flutter not found in PATH"
    return 1
  fi

  # Dependencies
  if [ -f "${PROJECT_DIR}/pubspec.lock" ]; then
    ok "Dependencies: pubspec.lock exists"
  else
    warn "Dependencies: pubspec.lock not found. Run 'flutter pub get'"
  fi

  # App identifier
  info "Bundle ID: $BUNDLE_ID"
  info "Version: $VERSION"

  # Signing certificates
  echo ""
  info "Checking code signing certificates..."

  CERTS="$(security find-identity -v -p codesigning ~/Library/Keychains/login.keychain-db 2>/dev/null || true)"
  if echo "$CERTS" | grep -q "Apple Development"; then
    ok "Apple Development certificate found"
  else
    warn "Apple Development certificate not found (needed for debug builds)"
  fi

  if echo "$CERTS" | grep -q "3rd Party Mac Developer"; then
    ok "Apple Distribution certificate found"
  elif echo "$CERTS" | grep -q "Developer ID"; then
    ok "Developer ID certificate found (for direct distribution)"
  else
    warn "No distribution certificate found. Install from developer.apple.com"
  fi

  # Team ID
  if [ -n "$TEAM_ID" ]; then
    ok "Team ID: $TEAM_ID"
  else
    warn "DEVELOPMENT_TEAM not set. Set via env var or Xcode project settings."
    echo "       export DEVELOPMENT_TEAM=YOUR_TEAM_ID"
  fi

  # App Store Connect
  echo ""
  info "App Store Connect metadata location: ${DMG_DIR}/AppStore/"
  info "Screenshots location: ${SCREENSHOTS_DIR}/"

  echo ""
  info "To complete App Store submission:"
  echo "  1. Create app record in App Store Connect"
  echo "  2. Upload build via Xcode Organizer or altool"
  echo "  3. Submit screenshots & metadata"
  echo "  4. Submit for review"
}

# ── Build release ──────────────────────────────────────────────────────
build_release() {
  echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║     ClarityMelt — Building Release                      ║${NC}"
  echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
  echo ""

  cd "$PROJECT_DIR"

  info "Installing dependencies..."
  flutter pub get

  info "Running code generator (Drift)..."
  dart run build_runner build --delete-conflicting-outputs 2>&1 || true

  info "Building macOS release..."
  flutter build macos --release

  if [ -d "$RELEASE_APP" ]; then
    ok "Build succeeded: $RELEASE_APP"

    # Show app info
    info "App details:"
    /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$RELEASE_APP/Contents/Info.plist" 2>/dev/null && \
      echo "  Version: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$RELEASE_APP/Contents/Info.plist")" || true
    /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$RELEASE_APP/Contents/Info.plist" 2>/dev/null && \
      echo "  Build: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$RELEASE_APP/Contents/Info.plist")" || true
    /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$RELEASE_APP/Contents/Info.plist" 2>/dev/null && \
      echo "  Bundle ID: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$RELEASE_APP/Contents/Info.plist")" || true

    SIZE="$(du -sh "$RELEASE_APP" | cut -f1)"
    info "App size: $SIZE"
  else
    err "Build failed: $RELEASE_APP not found"
    exit 1
  fi
}

# ── Archive for App Store ──────────────────────────────────────────────
archive_app() {
  echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║     ClarityMelt — Archiving for App Store               ║${NC}"
  echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
  echo ""

  cd "$PROJECT_DIR"

  # Ensure build exists
  if [ ! -d "$RELEASE_APP" ]; then
    info "No release build found. Building first..."
    build_release
  fi

  MACOS_DIR="${PROJECT_DIR}/macos"

  info "Creating Xcode archive..."

  # Build archive using xcodebuild
  TEAM_ID_ARG=""
  if [ -n "$TEAM_ID" ]; then
    TEAM_ID_ARG="DEVELOPMENT_TEAM=$TEAM_ID"
  fi

  xcodebuild archive \
    -workspace "${MACOS_DIR}/Runner.xcworkspace" \
    -scheme Runner \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    $TEAM_ID_ARG \
    CODE_SIGN_IDENTITY="Apple Development" \
    CODE_SIGN_STYLE=Automatic \
    | tail -20

  if [ -d "$ARCHIVE_PATH" ]; then
    ok "Archive created: $ARCHIVE_PATH"
  else
    err "Archive creation failed"
    exit 1
  fi
}

# ── Export for App Store ────────────────────────────────────────────────
export_app() {
  echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║     ClarityMelt — Exporting for App Store                ║${NC}"
  echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
  echo ""

  if [ ! -d "$ARCHIVE_PATH" ]; then
    err "No archive found. Run 'archive' first."
    exit 1
  fi

  mkdir -p "$EXPORT_DIR"

  # Create export options plist
  EXPORT_PLIST="${EXPORT_DIR}/ExportOptions.plist"
  cat > "$EXPORT_PLIST" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>teamID</key>
	<string>${TEAM_ID}</string>
	<key>uploadSymbols</key>
	<true/>
	<key>uploadBitcode</key>
	<false/>
	<key>signingStyle</key>
	<string>automatic</string>
</dict>
</plist>
PLIST

  info "Exporting archive..."

  if ! xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_PLIST" 2>&1; then
    echo ""
    warn "Export failed. This usually means distribution certificates/provisioning profiles are not installed."
    echo ""
    echo "  To fix this, you need either:"
    echo "    1. A 'Mac Installer Distribution' certificate + App Store provisioning profile (for App Store)"
    echo "    2. A 'Developer ID Installer' certificate (for direct distribution)"
    echo ""
    echo "  Install certificates via Xcode > Settings > Accounts > Manage Certificates"
    echo "  Or create them at https://developer.apple.com/account/resources/certificates/add"
    echo ""
    echo "  The archive was created successfully at:"
    echo "    $ARCHIVE_PATH"
    echo ""
    echo "  You can also upload the archive via Xcode Organizer:"
    echo "    Xcode > Window > Organizer > Distribute App"
    echo ""
    return 1
  fi

  if [ -d "${EXPORT_DIR}/ClarityMelt.pkg" ]; then
    ok "Package created: ${EXPORT_DIR}/ClarityMelt.pkg"
  elif [ -d "${EXPORT_DIR}/claritymelt_desktop.pkg" ]; then
    ok "Package created: ${EXPORT_DIR}/claritymelt_desktop.pkg"
  else
    warn "No .pkg found in export directory. Contents:"
    ls -la "${EXPORT_DIR}/"
  fi
}

# ── Create DMG ─────────────────────────────────────────────────────────
create_dmg() {
  echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║     ClarityMelt — Creating DMG for Direct Distribution   ║${NC}"
  echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
  echo ""

  if [ ! -d "$RELEASE_APP" ]; then
    info "No release build found. Building first..."
    build_release
  fi

  DMG_DIR="${BUILD_DIR}/macos/Distribution"
  DMG_NAME="ClarityMelt-${VERSION}.dmg"
  DMG_PATH="${DMG_DIR}/${DMG_NAME}"
  DMG_STAGING="${DMG_DIR}/staging"

  rm -rf "${DMG_DIR}"
  mkdir -p "${DMG_STAGING}"

  # Copy app to staging
  cp -R "$RELEASE_APP" "${DMG_STAGING}/"
  ln -s /Applications "${DMG_STAGING}/Applications"

  # Create DMG
  info "Creating DMG: ${DMG_NAME}..."

  hdiutil create \
    -volname "ClarityMelt" \
    -srcfolder "${DMG_STAGING}" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

  # Clean up staging
  rm -rf "${DMG_STAGING}"

  if [ -f "$DMG_PATH" ]; then
    SIZE="$(du -sh "$DMG_PATH" | cut -f1)"
    ok "DMG created: ${DMG_PATH} (${SIZE})"
  else
    err "DMG creation failed"
    exit 1
  fi
}

# ── Notarize DMG ───────────────────────────────────────────────────────
notarize_dmg() {
  local DMG_PATH="${BUILD_DIR}/macos/Distribution/ClarityMelt-${VERSION}.dmg"

  if [ ! -f "$DMG_PATH" ]; then
    err "DMG not found at ${DMG_PATH}. Run 'dmg' first."
    exit 1
  fi

  if [ -z "${APPLE_ID_EMAIL:-}" ] || [ -z "${APPLE_ID_PASSWORD:-}" ] || [ -z "$TEAM_ID" ]; then
    err "Notarization requires APPLE_ID_EMAIL, APPLE_ID_PASSWORD, and DEVELOPMENT_TEAM env vars."
    echo ""
    echo "  export APPLE_ID_EMAIL=your@email.com"
    echo "  export APPLE_ID_PASSWORD=app-specific-password"
    echo "  export DEVELOPMENT_TEAM=YOUR_TEAM_ID"
    echo ""
    echo "  See: https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution"
    exit 1
  fi

  info "Submitting DMG for notarization..."
  SUBMIT_OUTPUT="$(xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID_EMAIL" \
    --password "$APPLE_ID_PASSWORD" \
    --team-id "$TEAM_ID" 2>&1)"
  echo "$SUBMIT_OUTPUT"

  SUBMISSION_ID="$(echo "$SUBMIT_OUTPUT" | grep -oE 'id: [a-f0-9-]+' | head -1 | cut -d' ' -f2)"
  if [ -n "$SUBMISSION_ID" ]; then
    info "Notarization submitted. Submission ID: $SUBMISSION_ID"
    info "Waiting for notarization to complete..."
    xcrun notarytool wait "$SUBMISSION_ID" \
      --apple-id "$APPLE_ID_EMAIL" \
      --password "$APPLE_ID_PASSWORD" \
      --team-id "$TEAM_ID"

    info "Stapling notarization ticket..."
    xcrun stapler staple "$DMG_PATH"

    ok "DMG notarized and stapled: ${DMG_PATH}"
  else
    warn "Could not get submission ID. Check notarization status manually:"
    echo "  xcrun notarytool log <submission-id> --apple-id \$APPLE_ID_EMAIL --password \$APPLE_ID_PASSWORD --team-id \$TEAM_ID"
  fi
}

# ── Generate screenshots ───────────────────────────────────────────────
generate_screenshots() {
  echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║     ClarityMelt — Generating Screenshots                ║${NC}"
  echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
  echo ""

  cd "$PROJECT_DIR"
  bash ./tool/screenshot.sh manual
}

# ── App Store metadata ─────────────────────────────────────────────────
create_metadata() {
  echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║     ClarityMelt — App Store Metadata                     ║${NC}"
  echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
  echo ""

  METADATA_DIR="${BUILD_DIR}/macos/Distribution/AppStore"
  mkdir -p "$METADATA_DIR"

  # Create metadata JSON for reference
  cat > "${METADATA_DIR}/metadata.json" << 'EOF'
{
  "app_name": "ClarityMelt",
  "bundle_id": "com.claritymelt.app",
  "primary_category": "Developer Tools",
  "secondary_category": "Utilities",
  "sku": "claritymelt-macos-001",

  "locale": "en-US",
  "title": "ClarityMelt",
  "subtitle": "Infrastructure management made clear",
  "description": "ClarityMelt connects your cloud infrastructure into a single, clear view. Manage machines, domains, and DNS records across OVH, Hetzner, Cloudflare, and Namecheap — all from one native macOS app.\n\n• Machines — View VPS instances and dedicated servers from OVH and Hetzner, linked to their DNS records\n• Domains — Browse domains from Cloudflare, Namecheap, and OVH with DNS zone info\n• DNS Records — Manage Cloudflare DNS records with full CRUD operations\n• Providers — Add and manage org-scoped API credentials (AES-256 encrypted)\n• Products — Group infrastructure resources into deployed services\n• Uncloud — Manage self-hosted infrastructure with Uncloud cluster contexts\n\nAll credentials are encrypted with AES-256 before storage. Data is cached locally in SQLite for instant reads, with live sync to refresh from provider APIs.",
  "keywords": [
    "infrastructure",
    "devops",
    "cloud",
    "dns",
    "server",
    "monitoring",
    "ovh",
    "hetzner",
    "cloudflare",
    "namecheap",
    "vps",
    "domain",
    "ssh",
    "sysadmin"
  ],

  "support_url": "https://claritymelt.com/support",
  "marketing_url": "https://claritymelt.com",
  "privacy_url": "https://claritymelt.com/privacy",

  "whats_new": "Initial release — infrastructure management with clear connections between machines, domains, and DNS records. Encrypted credential storage. Multi-provider support (OVH, Hetzner, Cloudflare, Namecheap).",

  "screenshots": {
    "1280x800": "MacBook Air 13-inch",
    "1440x900": "MacBook Air 13-inch (scaled)",
    "2560x1600": "MacBook Air/Pro 13-inch Retina",
    "2880x1800": "MacBook Pro 15/16-inch Retina"
  },

  "review_notes": "ClarityMelt requires API credentials from at least one supported cloud provider (OVH, Hetzner, Cloudflare, or Namecheap) to display infrastructure data. Credentials are entered in the Providers tab and encrypted locally.\n\nFor review purposes, you can use test credentials with read-only access.\n\nTest account information is available upon request.",

  "review_demo_account": {
    "info": "Contact developer for test API credentials"
  }
}
EOF

  ok "Metadata created: ${METADATA_DIR}/metadata.json"

  # Create a readable version too
  cat > "${METADATA_DIR}/README.md" << 'EOF'
# ClarityMelt — App Store Submission

## App Information

| Field | Value |
|-------|-------|
| **App Name** | ClarityMelt |
| **Bundle ID** | com.claritymelt.app |
| **Category** | Developer Tools |
| **Secondary** | Utilities |
| **Version** | See pubspec.yaml |

## Description

ClarityMelt connects your cloud infrastructure into a single, clear view. Manage machines, domains, and DNS records across OVH, Hetzner, Cloudflare, and Namecheap — all from one native macOS app.

### Features

- **Machines** — View VPS instances and dedicated servers from OVH and Hetzner, linked to their DNS records
- **Domains** — Browse domains from Cloudflare, Namecheap, and OVH with DNS zone info
- **DNS Records** — Manage Cloudflare DNS records with full CRUD operations
- **Providers** — Add and manage org-scoped API credentials (AES-256 encrypted)
- **Products** — Group infrastructure resources into deployed services
- **Uncloud** — Manage self-hosted infrastructure with Uncloud cluster contexts

All credentials are encrypted with AES-256 before storage. Data is cached locally in SQLite for instant reads, with live sync to refresh from provider APIs.

## Screenshots

Required screenshot sizes for Mac App Store:

| Resolution | Device |
|-----------|--------|
| 1280 × 800 | MacBook Air 13-inch |
| 1440 × 900 | MacBook Air 13-inch (scaled) |
| 2560 × 1600 | MacBook Air/Pro 13-inch Retina |
| 2880 × 1800 | MacBook Pro 15/16-inch Retina |

Generate screenshots with:
```bash
./tool/screenshot.sh manual   # Interactive
./tool/screenshot.sh auto      # Automated
```

## Build & Archive

```bash
# Build release
flutter build macos --release

# Or use the packaging script
./tool/package.sh build     # Build release
./tool/package.sh archive   # Archive for App Store
./tool/package.sh dmg       # Create DMG for direct distribution
./tool/package.sh all       # Full pipeline
```

## App Store Connect Upload

1. Open Xcode → Organizer
2. Select the archive
3. Click "Distribute App" → "Mac App Store"
4. Follow the upload wizard

Or via command line:
```bash
xcrun altool --upload-app \
  --type macos \
  --file "build/macos/ClarityMelt.pkg" \
  --apiKey YOUR_API_KEY \
  --apiIssuer YOUR_ISSUER_ID
```

## Direct Distribution (DMG)

For distribution outside the App Store, notarize the DMG:
```bash
export APPLE_ID_EMAIL=your@email.com
export APPLE_ID_PASSWORD=app-specific-password
export DEVELOPMENT_TEAM=YOUR_TEAM_ID
./tool/package.sh dmg
./tool/package.sh notarize
```

## Review Notes

ClarityMelt requires API credentials from at least one supported cloud provider
(OVH, Hetzner, Cloudflare, or Namecheap) to display infrastructure data.
Credentials are entered in the Providers tab and encrypted locally.

For review purposes, test credentials with read-only access can be provided upon request.
EOF

  ok "Metadata README created: ${METADATA_DIR}/README.md"

  # Create screenshot size reference
  mkdir -p "${METADATA_DIR}/screenshots"
  for SIZE in "1280x800" "1440x900" "2560x1600" "2880x1800"; do
    mkdir -p "${METADATA_DIR}/screenshots/${SIZE}"
  done
  ok "Screenshot directories created: ${METADATA_DIR}/screenshots/"

  echo ""
  info "Next steps:"
  echo "  1. Generate screenshots:  ./tool/screenshot.sh manual"
  echo "  2. Copy screenshots to:   ${METADATA_DIR}/screenshots/"
  echo "  3. Archive the app:       ./tool/package.sh archive"
  echo "  4. Upload to App Store Connect via Xcode Organizer"
  echo "  5. Add metadata in App Store Connect"
  echo "  6. Submit for review"
}

# ── Full pipeline ───────────────────────────────────────────────────────
do_all() {
  build_release
  echo ""
  create_dmg
  echo ""
  create_metadata
  echo ""
  info "🎉 Package pipeline complete!"
  echo ""
  info "Output files:"
  echo "  App:     ${RELEASE_APP}"
  echo "  DMG:     ${BUILD_DIR}/macos/Distribution/ClarityMelt-${VERSION}.dmg"
  echo "  Metadata: ${BUILD_DIR}/macos/Distribution/AppStore/"
}

# ── Main ────────────────────────────────────────────────────────────────
COMMAND="${1:-all}"

case "$COMMAND" in
  check)
    check_setup
    ;;
  build)
    build_release
    ;;
  archive)
    archive_app
    ;;
  export)
    export_app
    ;;
  dmg)
    create_dmg
    ;;
  notarize)
    notarize_dmg
    ;;
  metadata)
    create_metadata
    ;;
  screenshots)
    generate_screenshots
    ;;
  all)
    do_all
    ;;
  *)
    echo "ClarityMelt macOS Package Builder"
    echo ""
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  check        Check setup (Xcode, Flutter, certs)"
    echo "  build        Build release .app"
    echo "  archive      Archive for App Store"
    echo "  export       Export archive for App Store"
    echo "  dmg          Create DMG for direct distribution"
    echo "  notarize     Notarize DMG (requires env vars)"
    echo "  metadata     Create App Store metadata"
    echo "  screenshots  Generate screenshots"
    echo "  all          Build + DMG + metadata"
    echo ""
    echo "Environment variables:"
    echo "  DEVELOPMENT_TEAM     Apple Team ID for signing"
    echo "  APPLE_ID_EMAIL       Apple ID for notarization"
    echo "  APPLE_ID_PASSWORD    App-specific password for notarization"
    exit 1
    ;;
esac