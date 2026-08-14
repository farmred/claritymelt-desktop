#!/bin/bash
# ClarityMelt Distribution Script
# ==================================
# This script handles creating and uploading a distributable macOS app.
#
# PREREQUISITES (choose ONE path):
#
# PATH A — App Store Distribution:
#   1. Apple Distribution certificate (create in Xcode > Settings > Accounts > Manage Certificates)
#   2. App Store Connect API key OR app-specific password
#
# PATH B — Direct Distribution (outside App Store):
#   1. Developer ID Application certificate (create in Xcode > Settings > Accounts > Manage Certificates)
#   2. App-specific password for notarization
#
# See: https://developer.apple.com/help/account/create-certificates/create-a-distribution-certificate

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARCHIVE_PATH="$PROJECT_DIR/macos/build/ClarityMelt.xcarchive"
APP_NAME="ClarityMelt"
BUNDLE_ID="com.claritymelt.app"
TEAM_ID="FW49BGQK63"

echo "=== ClarityMelt Distribution ==="
echo ""

# ─── Step 1: Create App Store Connect API credentials ───
# To upload, you need an App Store Connect API Key:
#   https://appstoreconnect.apple.com/access/integrations/api
# Click "Generate API Key" (name it e.g. "CI", access: Admin)
# Download the .p8 file and save it to: ~/private_keys/AuthKey_XXXXXXXXXX.p8
# Note the Key ID and Issuer ID shown on the page.

# ─── Step 2: Store credentials for notarytool (one-time setup) ───
# Option A: App Store Connect API Key (recommended)
#   xcrun notarytool store-credentials "notary-api-key" \
#     --key ~/private_keys/AuthKey_XXXXXXXXXX.p8 \
#     --key-id YOUR_KEY_ID \
#     --issuer YOUR_ISSUER_ID
#
# Option B: Apple ID + app-specific password
#   xcrun notarytool store-credentials "notary-apple-id" \
#     --apple-id "your@email.com" \
#     --team-id FW49BGQK63 \
#     --password xxxx-xxxx-xxxx-xxxx

# ─── Step 3: Choose your distribution method ───
echo "Choose distribution method:"
echo "  1) App Store Connect (upload .pkg for Mac App Store)"
echo "  2) Developer ID (notarized .dmg for direct distribution)"
echo ""
read -r -p "Enter choice [1/2]: " CHOICE

if [ "$CHOICE" = "1" ]; then
    # ═══════════════════════════════════════════════════════════
    # APP STORE DISTRIBUTION
    # ═══════════════════════════════════════════════════════════

    # Requires: Apple Distribution certificate + provisioning profile
    echo ""
    echo "--- App Store Distribution ---"

    # Create a .pkg from the archive for App Store upload
    echo "Creating .pkg for App Store Connect..."
    mkdir -p "$PROJECT_DIR/build/distribution"

    xcrun productbuild \
        --component "$ARCHIVE_PATH/Products/Applications/$APP_NAME.app" /Applications \
        --product-name "$APP_NAME" \
        "$PROJECT_DIR/build/distribution/$APP_NAME.pkg"

    echo ""
    echo "Package created: $PROJECT_DIR/build/distribution/$APP_NAME.pkg"
    echo ""
    echo "To upload to App Store Connect, use ONE of:"
    echo ""
    echo "  # Option 1: Xcode Organizer (easiest)"
    echo "  #   Open Xcode > Window > Organizer > Archives > Distribute App"
    echo ""
    echo "  # Option 2: xcrun altool (with API key)"
    echo "  xcrun altool --upload-app \\"
    echo "    -f $PROJECT_DIR/build/distribution/$APP_NAME.pkg \\"
    echo "    -t macos \\"
    echo "    --apiKey YOUR_API_KEY_ID \\"
    echo "    --apiIssuer YOUR_ISSUER_ID"
    echo ""
    echo "  # Option 3: xcrun notarytool (for validation)"
    echo "  xcrun notarytool submit $PROJECT_DIR/build/distribution/$APP_NAME.pkg \\"
    echo "    --keychain-profile notary-api-key --wait"

elif [ "$CHOICE" = "2" ]; then
    # ═══════════════════════════════════════════════════════════
    # DEVELOPER ID DISTRIBUTION (Direct Distribution)
    # ═══════════════════════════════════════════════════════════

    # Requires: Developer ID Application certificate + notarization
    echo ""
    echo "--- Developer ID Distribution ---"

    # Create a zip for notarization
    echo "Creating zip for notarization..."
    cd "$ARCHIVE_PATH/Products/Applications"
    ditto -c -k --keepParent "$APP_NAME.app" "$PROJECT_DIR/build/distribution/$APP_NAME.zip"

    echo ""
    echo "To notarize and staple:"
    echo ""
    echo "  # Submit for notarization"
    echo "  xcrun notarytool submit $PROJECT_DIR/build/distribution/$APP_NAME.zip \\"
    echo "    --keychain-profile notary-api-key --wait"
    echo ""
    echo "  # Once approved, staple the ticket"
    echo "  xcrun stapler staple \"$ARCHIVE_PATH/Products/Applications/$APP_NAME.app\""
    echo ""
    echo "  # Then create a DMG from the stapled app"
    echo "  hdiutil create -volname \"$APP_NAME\" -srcfolder \\"
    echo "    <(cp -R \"$ARCHIVE_PATH/Products/Applications/$APP_NAME.app\" /tmp/dmg/ && \\"
    echo"     ln -s /Applications /tmp/dmg/Applications) \\"
    echo "    -ov -format UDZO \"$PROJECT_DIR/build/distribution/$APP_NAME.dmg\""

else
    echo "Invalid choice. Exiting."
    exit 1
fi