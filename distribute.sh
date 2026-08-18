#!/bin/bash
# ClarityMelt Distribution Script
# ==================================
# Quick-start for building and uploading to the App Store.
#
# For full control, use the dedicated scripts:
#   ./tool/package.sh          # Build, archive, DMG, notarize
#   ./tool/appstore_upload.sh  # Upload to App Store Connect (JWT auth)
#
# PREREQUISITES:
#   1. Apple Distribution certificate installed
#      (Xcode > Settings > Accounts > Manage Certificates)
#   2. App Store Connect API key for JWT authentication:
#      https://appstoreconnect.apple.com/access/integrations/api
#   3. .p8 key file saved to ~/private_keys/AuthKey_XXXXXXXXXX.p8
#
# Environment variables:
#   ASC_API_KEY_ID    App Store Connect API Key ID
#   ASC_ISSUER_ID     App Store Connect Issuer ID
#   ASC_P8_PATH       Path to .p8 key file (default: ~/private_keys/AuthKey_${ASC_API_KEY_ID}.p8)
#   DEVELOPMENT_TEAM  Apple Team ID (default: FW49BGQK63)

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== ClarityMelt Distribution ==="
echo ""
echo "Choose distribution method:"
echo "  1) App Store Connect (upload .pkg via JWT auth)"
echo "  2) Developer ID (notarized .dmg for direct distribution)"
echo "  3) Build only (archive + export .pkg)"
echo ""
read -r -p "Enter choice [1/2/3]: " CHOICE

case "$CHOICE" in
  1)
    # ═══════════════════════════════════════════════════════════
    # APP STORE UPLOAD (JWT Authentication)
    # ═══════════════════════════════════════════════════════════
    echo ""
    echo "--- App Store Connect Upload (JWT Auth) ---"
    echo ""
    echo "This will:"
    echo "  1. Build a release .app"
    echo "  2. Archive it for App Store distribution"
    echo "  3. Export a .pkg"
    echo "  4. Upload to App Store Connect using JWT authentication"
    echo ""

    if [ -z "${ASC_API_KEY_ID:-}" ] || [ -z "${ASC_ISSUER_ID:-}" ]; then
      echo "⚠️  API credentials not set. You need to configure them first."
      echo ""
      echo "  1. Go to https://appstoreconnect.apple.com/access/integrations/api"
      echo "  2. Generate an API Key (name: e.g. 'CI Upload', access: Admin)"
      echo "  3. Download the .p8 file"
      echo "  4. Save it: cp ~/Downloads/AuthKey_XXXXXXXXXX.p8 ~/private_keys/"
      echo "  5. Set environment variables:"
      echo ""
      echo "     export ASC_API_KEY_ID=XXXXXXXXXX"
      echo "     export ASC_ISSUER_ID=12345678-abcd-ef01-2345-678901234567"
      echo "     export ASC_P8_PATH=~/private_keys/AuthKey_XXXXXXXXXX.p8"
      echo ""
      echo "Or pass them as flags:"
      echo "  ./tool/appstore_upload.sh upload --key-id XXXXXXXXXX --issuer-id 12345678-abcd-..."
      echo ""
      echo "Run './tool/appstore_upload.sh jwt' to test your credentials."
      exit 1
    fi

    exec "${PROJECT_DIR}/tool/appstore_upload.sh" all
    ;;

  2)
    # ═══════════════════════════════════════════════════════════
    # DEVELOPER ID DISTRIBUTION (Direct Distribution)
    # ═══════════════════════════════════════════════════════════
    echo ""
    echo "--- Developer ID Distribution ---"
    echo ""
    echo "This will build, create a DMG, and notarize it."
    echo ""

    if [ -z "${APPLE_ID_EMAIL:-}" ] || [ -z "${DEVELOPMENT_TEAM:-}" ]; then
      echo "⚠️  Credentials needed for notarization."
      echo ""
      echo "  export APPLE_ID_EMAIL=your@email.com"
      echo "  export DEVELOPMENT_TEAM=FW49BGQK63"
      echo ""
      echo "  # For notarization with App Store Connect API key (recommended):"
      echo "  xcrun notarytool store-credentials 'notary-api-key' \\"
      echo "    --key ~/private_keys/AuthKey_XXXXXXXXXX.p8 \\"
      echo "    --key-id XXXXXXXXXX \\"
      echo "    --issuer 12345678-abcd-..."
      echo ""
      echo "  # Or with an app-specific password:"
      echo "  export APPLE_ID_PASSWORD=xxxx-xxxx-xxxx-xxxx"
      echo ""
      exit 1
    fi

    exec "${PROJECT_DIR}/tool/package.sh" all
    ;;

  3)
    # ═══════════════════════════════════════════════════════════
    # BUILD ONLY
    # ═══════════════════════════════════════════════════════════
    echo ""
    echo "--- Build + Archive ---"
    echo ""
    exec "${PROJECT_DIR}/tool/appstore_upload.sh" build
    ;;

  *)
    echo "Invalid choice. Exiting."
    exit 1
    ;;
esac