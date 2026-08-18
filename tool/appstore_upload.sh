#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════
# ClarityMelt — App Store Upload via Transporter / altool (JWT Auth)
#
# Uploads a built .app or .pkg to App Store Connect using
# JSON Web Token (JWT) authentication with an App Store Connect API Key.
#
# PREREQUISITES (one-time setup):
#
# 1. Create an App Store Connect API Key:
#    - Go to https://appstoreconnect.apple.com/access/integrations/api
#    - Click "Generate API Key"
#    - Name it (e.g. "CI Upload")
#    - Access: Admin (or App Manager for uploads only)
#    - Download the .p8 file (you can only download it ONCE)
#    - Note the Key ID (e.g. "ABC12DEF34") and Issuer ID (e.g. "12345678-1234-...")
#
# 2. Store the API key:
#    mkdir -p ~/private_keys
#    cp ~/Downloads/AuthKey_ABC12DEF34.p8 ~/private_keys/
#
# 3. Set environment variables (or pass flags):
#    export ASC_API_KEY_ID="ABC12DEF34"
#    export ASC_ISSUER_ID="12345678-1234-..."
#    export ASC_P8_PATH="$HOME/private_keys/AuthKey_ABC12DEF34.p8"
#
#    Or store credentials in keychain for notarytool:
#    xcrun notarytool store-credentials "notary-api-key" \
#      --key ~/private_keys/AuthKey_ABC12DEF34.p8 \
#      --key-id ABC12DEF34 \
#      --issuer 12345678-1234-...
#
# USAGE:
#   ./tool/appstore_upload.sh                    # Build + archive + upload
#   ./tool/appstore_upload.sh upload              # Upload existing .pkg only
#   ./tool/appstore_upload.sh build              # Build + archive only
#   ./tool/appstore_upload.sh validate            # Validate without uploading
#   ./tool/appstore_upload.sh jwt                # Generate JWT for debugging
# ═══════════════════════════════════════════════════════════════════════

set -euo pipefail

# ── Configuration ───────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${PROJECT_DIR}/build/macos"
APP_NAME="ClarityMelt"
BUNDLE_ID="com.claritymelt.app"
TEAM_ID="FW49BGQK63"
ARCHIVE_PATH="${BUILD_DIR}/ClarityMelt.xcarchive"
PKG_PATH="${BUILD_DIR}/Export/${APP_NAME}.pkg"
EXPORT_DIR="${BUILD_DIR}/Export"
VERSION="$(grep '^version:' "${PROJECT_DIR}/pubspec.yaml" | head -1 | sed 's/version: //;s/+.*//;s/ //g')"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()  { echo -e "${CYAN}ℹ️  $1${NC}"; }
ok()    { echo -e "${GREEN}✅ $1${NC}"; }
warn()  { echo -e "${YELLOW}⚠️  $1${NC}"; }
err()   { echo -e "${RED}❌ $1${NC}"; }

# ── Environment Variables ──────────────────────────────────────────────
ASC_API_KEY_ID="${ASC_API_KEY_ID:-}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:-}"
ASC_P8_PATH="${ASC_P8_PATH:-$HOME/private_keys/AuthKey_${ASC_API_KEY_ID}.p8}"

# ── Validate API credentials ──────────────────────────────────────────
check_credentials() {
  local missing=0

  if [ -z "$ASC_API_KEY_ID" ]; then
    err "ASC_API_KEY_ID not set"
    echo "   Get it from: https://appstoreconnect.apple.com/access/integrations/api"
    echo "   Then: export ASC_API_KEY_ID=YOUR_KEY_ID"
    missing=1
  fi

  if [ -z "$ASC_ISSUER_ID" ]; then
    err "ASC_ISSUER_ID not set"
    echo "   Get it from: https://appstoreconnect.apple.com/access/integrations/api"
    echo "   Then: export ASC_ISSUER_ID=YOUR_ISSUER_ID"
    missing=1
  fi

  # Resolve P8 path
  if [ -z "$ASC_API_KEY_ID" ]; then
    ASC_P8_PATH="${ASC_P8_PATH:-$HOME/private_keys/AuthKey_.p8}"
  else
    ASC_P8_PATH="${ASC_P8_PATH:-$HOME/private_keys/AuthKey_${ASC_API_KEY_ID}.p8}"
  fi

  if [ ! -f "$ASC_P8_PATH" ]; then
    err "API key .p8 file not found: $ASC_P8_PATH"
    echo "   Download it from App Store Connect > Integrations > App Store Connect API"
    echo "   Then: cp ~/Downloads/AuthKey_${ASC_API_KEY_ID}.p8 ~/private_keys/"
    echo ""
    echo "   Alternatively, set ASC_P8_PATH explicitly:"
    echo "   export ASC_P8_PATH=/path/to/AuthKey_XXXXXXXX.p8"
    missing=1
  fi

  if [ "$missing" -eq 1 ]; then
    echo ""
    echo -e "${BOLD}Setup instructions:${NC}"
    echo ""
    echo "  1. Go to https://appstoreconnect.apple.com/access/integrations/api"
    echo "  2. Click 'Generate API Key' (name: e.g. 'CI', access: Admin)"
    echo "  3. Note the Key ID and Issuer ID"
    echo "  4. Download the .p8 file"
    echo "  5. Run:"
    echo ""
    echo "     mkdir -p ~/private_keys"
    echo "     cp ~/Downloads/AuthKey_XXXXXXXXXX.p8 ~/private_keys/"
    echo ""
    echo "  6. Set environment variables:"
    echo ""
    echo "     export ASC_API_KEY_ID=XXXXXXXXXX"
    echo "     export ASC_ISSUER_ID=12345678-abcd-ef01-2345-678901234567"
    echo "     export ASC_P8_PATH=~/private_keys/AuthKey_XXXXXXXXXX.p8"
    echo ""
    echo "  7. (Optional) Store for notarytool:"
    echo ""
    echo "     xcrun notarytool store-credentials 'notary-api-key' \\"
    echo "       --key ~/private_keys/AuthKey_XXXXXXXXXX.p8 \\"
    echo "       --key-id XXXXXXXXXX \\"
    echo "       --issuer 12345678-abcd-ef01-2345-678901234567"
    echo ""
    exit 1
  fi

  ok "API Key ID: $ASC_API_KEY_ID"
  ok "Issuer ID: $ASC_ISSUER_ID"
  ok "P8 file: $ASC_P8_PATH"
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

  info "Running code generator..."
  dart run build_runner build --delete-conflicting-outputs 2>&1 || true

  info "Building macOS release..."
  flutter build macos --release

  local release_app="${BUILD_DIR}/Build/Products/Release/${APP_NAME}.app"
  if [ -d "$release_app" ]; then
    ok "Build succeeded: $release_app"
    local size
    size="$(du -sh "$release_app" | cut -f1)"
    info "App size: $size"
    info "Version: $VERSION"
  else
    err "Build failed: $release_app not found"
    exit 1
  fi
}

# ── Archive ─────────────────────────────────────────────────────────────
archive_app() {
  echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║     ClarityMelt — Archiving for App Store               ║${NC}"
  echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
  echo ""

  cd "$PROJECT_DIR"
  local macos_dir="${PROJECT_DIR}/macos"

  # Remove stale archive
  rm -rf "$ARCHIVE_PATH"

  info "Creating Xcode archive..."
  info "  Team: $TEAM_ID"
  info "  Identity: Apple Development"

  xcodebuild archive \
    -workspace "${macos_dir}/Runner.xcworkspace" \
    -scheme Runner \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_IDENTITY="Apple Development" \
    CODE_SIGN_STYLE=Automatic \
    | tail -30

  if [ -d "$ARCHIVE_PATH" ]; then
    ok "Archive created: $ARCHIVE_PATH"
    local archive_size
    archive_size="$(du -sh "$ARCHIVE_PATH" | cut -f1)"
    info "Archive size: $archive_size"
  else
    err "Archive creation failed"
    exit 1
  fi
}

# ── Export .pkg ─────────────────────────────────────────────────────────
export_pkg() {
  echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║     ClarityMelt — Exporting .pkg for App Store           ║${NC}"
  echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
  echo ""

  if [ ! -d "$ARCHIVE_PATH" ]; then
    err "No archive found at $ARCHIVE_PATH"
    echo "   Run with 'build' or 'archive' first."
    exit 1
  fi

  mkdir -p "$EXPORT_DIR"

  # Create export options plist for App Store distribution
  local export_plist="${EXPORT_DIR}/ExportOptions.plist"
  cat > "$export_plist" << PLIST
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

  info "Exporting archive to .pkg..."
  info "  Method: app-store-connect"
  info "  Team: $TEAM_ID"

  if ! xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$export_plist" 2>&1; then
    echo ""
    err "Export failed. This usually means distribution certificates/provisioning profiles are not installed."
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

  # Find the .pkg (Xcode may name it differently)
  local found_pkg=""
  for pkg in "${EXPORT_DIR}"/*.pkg; do
    if [ -f "$pkg" ]; then
      found_pkg="$pkg"
      break
    fi
  done

  if [ -n "$found_pkg" ]; then
    PKG_PATH="$found_pkg"
    local pkg_size
    pkg_size="$(du -sh "$PKG_PATH" | cut -f1)"
    ok "Package created: $PKG_PATH ($pkg_size)"
  else
    warn "No .pkg found in export directory. Contents:"
    ls -la "${EXPORT_DIR}/"
    echo ""
    err "Export may have failed. Check the export log above."
    return 1
  fi
}

# ── Validate .pkg ──────────────────────────────────────────────────────
validate_pkg() {
  echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║     ClarityMelt — Validating Package                     ║${NC}"
  echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
  echo ""

  check_credentials

  if [ ! -f "$PKG_PATH" ]; then
    err "Package not found: $PKG_PATH"
    echo "   Run with 'build' or 'export' first."
    exit 1
  fi

  info "Validating package with App Store Connect..."
  info "  File: $PKG_PATH"
  info "  Key ID: $ASC_API_KEY_ID"
  info "  Issuer: $ASC_ISSUER_ID"

  xcrun altool --validate-app \
    -f "$PKG_PATH" \
    -t macos \
    --apiKey "$ASC_API_KEY_ID" \
    --apiIssuer "$ASC_ISSUER_ID" \
    2>&1

  local result=$?
  if [ $result -eq 0 ]; then
    ok "Package validation succeeded!"
  else
    err "Package validation failed (exit code: $result)"
    echo ""
    echo "Common issues:"
    echo "  - Missing or incorrect entitlements"
    echo "  - Invalid bundle ID or version"
    echo "  - Code signing issues"
    echo "  - API key lacks sufficient permissions"
    return $result
  fi
}

# ── Upload to App Store Connect ────────────────────────────────────────
upload_to_appstore() {
  echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║     ClarityMelt — Uploading to App Store Connect        ║${NC}"
  echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
  echo ""

  check_credentials

  if [ ! -f "$PKG_PATH" ]; then
    err "Package not found: $PKG_PATH"
    echo "   Run with 'build' first, or specify path with --pkg"
    exit 1
  fi

  local pkg_size
  pkg_size="$(du -sh "$PKG_PATH" | cut -f1)"

  info "Uploading to App Store Connect..."
  info "  File: $PKG_PATH ($pkg_size)"
  info "  Bundle ID: $BUNDLE_ID"
  info "  Version: $VERSION"
  info "  Key ID: $ASC_API_KEY_ID"
  info "  Issuer: $ASC_ISSUER_ID"
  echo ""

  # ── Upload using altool with JWT authentication ──
  # The --apiKey and --apiIssuer flags tell altool to generate a JWT
  # from the .p8 file located at ~/private_keys/AuthKey_<keyId>.p8
  # (or ASC_P8_PATH if set)
  xcrun altool --upload-app \
    -f "$PKG_PATH" \
    -t macos \
    --apiKey "$ASC_API_KEY_ID" \
    --apiIssuer "$ASC_ISSUER_ID" \
    2>&1

  local result=$?
  if [ $result -eq 0 ]; then
    echo ""
    ok "Upload succeeded! 🎉"
    echo ""
    echo -e "${BOLD}Next steps:${NC}"
    echo ""
    echo "  1. Go to https://appstoreconnect.apple.com"
    echo "  2. Navigate to your app → TestFlight or App Store tab"
    echo "  3. The build should appear within a few minutes"
    echo "  4. Apple will process the build (usually 5-30 min)"
    echo "  5. Once processing is complete, add it to your version"
    echo "  6. Submit for review"
    echo ""
    echo "  Monitor build status:"
    echo "    https://appstoreconnect.apple.com > My Apps > ClarityMelt > TestFlight"
  else
    echo ""
    err "Upload failed (exit code: $result)"
    echo ""
    echo "Common issues:"
    echo "  - Invalid API key or issuer ID"
    echo "  - .p8 file not found at expected path"
    echo "  - Bundle ID mismatch (must match App Store Connect record)"
    echo "  - Version/build number already used"
    echo "  - API key lacks Admin or App Manager role"
    echo "  - Package validation errors (run 'validate' first)"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Verify credentials: ./tool/appstore_upload.sh jwt"
    echo "  2. Validate package:   ./tool/appstore_upload.sh validate"
    echo "  3. Check .p8 path:    ls ~/private_keys/AuthKey_*.p8"
    echo "  4. Try with verbose:   xcrun altool --upload-app -f \"$PKG_PATH\" -t macos --apiKey $ASC_API_KEY_ID --apiIssuer $ASC_ISSUER_ID -v"
    return $result
  fi
}

# ── Generate JWT for debugging ─────────────────────────────────────────
generate_jwt() {
  echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║     ClarityMelt — JWT Authentication Debug              ║${NC}"
  echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
  echo ""

  check_credentials

  info "Testing JWT generation with your API key..."
  echo ""

  # Use altool's built-in JWT generation to verify credentials
  info "Generating JWT..."
  JWT_OUTPUT="$(xcrun altool --generate-jwt \
    --apiKey "$ASC_API_KEY_ID" \
    --apiIssuer "$ASC_ISSUER_ID" \
    2>&1 || true)"

  if echo "$JWT_OUTPUT" | grep -qi "error\|fail\|invalid"; then
    err "JWT generation failed:"
    echo "$JWT_OUTPUT"
    echo ""
    echo "Check that:"
    echo "  1. Your API Key ID is correct: $ASC_API_KEY_ID"
    echo "  2. Your Issuer ID is correct: $ASC_ISSUER_ID"
    echo "  3. The .p8 file exists at: $ASC_P8_PATH"
  else
    ok "JWT generation succeeded"
    echo ""
    info "Credential summary:"
    echo "  API Key ID:  $ASC_API_KEY_ID"
    echo "  Issuer ID:   $ASC_ISSUER_ID"
    echo "  P8 path:     $ASC_P8_PATH"
    echo "  Team ID:     $TEAM_ID"
    echo "  Bundle ID:   $BUNDLE_ID"
    echo "  Version:     $VERSION"
    echo ""
    info "The JWT is valid for 60 minutes per generation."
    info "altool handles JWT generation automatically with --apiKey/--apiIssuer."
  fi
}

# ── Full pipeline ──────────────────────────────────────────────────────
full_pipeline() {
  build_release
  echo ""
  archive_app
  echo ""
  if ! export_pkg; then
    echo ""
    err "Cannot continue without exported .pkg. Install distribution certificates and try again."
    echo "  See: https://developer.apple.com/account/resources/certificates/add"
    return 1
  fi
  echo ""
  validate_pkg
  echo ""
  upload_to_appstore
}

# ── Main ────────────────────────────────────────────────────────────────
COMMAND="${1:-upload}"
shift 2>/dev/null || true

# Parse flags
while [[ $# -gt 0 ]]; do
  case $1 in
    --pkg)
      PKG_PATH="$2"
      shift 2
      ;;
    --key-id)
      ASC_API_KEY_ID="$2"
      shift 2
      ;;
    --issuer-id)
      ASC_ISSUER_ID="$2"
      shift 2
      ;;
    --p8-path)
      ASC_P8_PATH="$2"
      shift
      ;;
    *)
      echo "Unknown flag: $1"
      exit 1
      ;;
  esac
done

case "$COMMAND" in
  build)
    build_release
    archive_app
    if ! export_pkg; then
      err "Export failed. Install distribution certificates to generate .pkg"
      exit 1
    fi
    ;;
  archive)
    archive_app
    ;;
  export)
    export_pkg
    ;;
  validate)
    validate_pkg
    ;;
  upload)
    upload_to_appstore
    ;;
  jwt)
    generate_jwt
    ;;
  all)
    full_pipeline
    ;;
  *)
    echo "ClarityMelt — App Store Upload Tool"
    echo ""
    echo "Usage: $0 <command> [flags]"
    echo ""
    echo "Commands:"
    echo "  all        Full pipeline: build → archive → export → validate → upload"
    echo "  build      Build release, archive, and export .pkg"
    echo "  archive    Archive the app (requires prior build)"
    echo "  export     Export .pkg from existing archive"
    echo "  validate    Validate .pkg with App Store Connect"
    echo "  upload     Upload .pkg to App Store Connect (default)"
    echo "  jwt        Test JWT authentication credentials"
    echo ""
    echo "Flags:"
    echo "  --pkg PATH        Path to .pkg file (default: ${PKG_PATH})"
    echo "  --key-id ID       App Store Connect API Key ID"
    echo "  --issuer-id ID    App Store Connect Issuer ID"
    echo "  --p8-path PATH    Path to .p8 key file"
    echo ""
    echo "Environment variables:"
    echo "  ASC_API_KEY_ID    App Store Connect API Key ID"
    echo "  ASC_ISSUER_ID     App Store Connect Issuer ID"
    echo "  ASC_P8_PATH       Path to .p8 key file"
    echo "                    (default: ~/private_keys/AuthKey_\${ASC_API_KEY_ID}.p8)"
    echo ""
    echo "Setup (one-time):"
    echo "  1. https://appstoreconnect.apple.com/access/integrations/api"
    echo "  2. Generate API Key (Admin access)"
    echo "  3. Download .p8 → ~/private_keys/AuthKey_XXXXXXXXXX.p8"
    echo "  4. export ASC_API_KEY_ID=XXXXXXXXXX"
    echo "  5. export ASC_ISSUER_ID=12345678-abcd-..."
    exit 1
    ;;
esac