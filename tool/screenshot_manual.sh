#!/usr/bin/env bash
# ────────────────────────────────────────────────────────────────────────
# ClarityMelt — Manual Screenshot Capture Helper
#
# This script automates resizing the macOS window and capturing screenshots
# using the running ClarityMelt app and macOS screencapture.
#
# Prerequisites:
#   - ClarityMelt app is running (flutter run -d macos or release build)
#   - macOS screencapture command available
#   - Accessibility permissions granted for Terminal/IDE
#
# Usage:
#   1. Start the app:  flutter run -d macos
#   2. Run this script:  ./tool/screenshot_manual.sh
#
# The script will:
#   - Resize the ClarityMelt window to each target dimension
#   - Pause for you to navigate to each tab
#   - Capture a screenshot at each size
# ────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${PROJECT_DIR}/screenshots"

# Target sizes: (name width height)
declare -A SIZES
SIZES["1280x800"]="1280 800"
SIZES["1440x900"]="1440 900"
SIZES["2560x1600"]="2560 1600"
SIZES["2880x1800"]="2880 1800"

# Tabs to capture
TABS=("machines" "domains" "dns" "providers" "products" "uncloud")

TARGET_SIZE="${1:-all}"

mkdir -p "$OUTPUT_DIR"

echo "╔══════════════════════════════════════════════════════════╗"
echo "║    ClarityMelt Manual Screenshot Capture                ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "⚠️  Make sure ClarityMelt is running before proceeding!"
echo ""
read -p "Press Enter to continue (or Ctrl+C to cancel)..."

APP_NAME="ClarityMelt"

for SIZE_NAME in "1280x800" "1440x900" "2560x1600" "2880x1800"; do
  if [[ "$TARGET_SIZE" != "all" && "$TARGET_SIZE" != "$SIZE_NAME" ]]; then
    continue
  fi

  read -r W H <<< "${SIZES[$SIZE_NAME]}"

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📸 Resizing to ${SIZE_NAME} (${W}×${H})"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # Resize the window via AppleScript
  osascript -e "
    tell application \"SystemEvents\"
      set appName to \"$APP_NAME\"
      if (name of processes) contains appName then
        tell process appName
          set frontmost to true
          set position of window 1 to {0, 0}
          set size of window 1 to {$W, $H}
        end tell
      else
        display dialog \"$APP_NAME is not running!\"
      end if
    end tell
  " 2>/dev/null || echo "⚠️  Could not resize window via AppleScript. Please resize manually to ${W}×${H}."

  sleep 1

  SIZE_DIR="$OUTPUT_DIR/$SIZE_NAME"
  mkdir -p "$SIZE_DIR"

  for TAB in "${TABS[@]}"; do
    echo ""
    echo "  🖥️  Navigate to the '$TAB' tab, then press Enter to capture..."
    read -p "     [Enter to capture / type 'skip' to skip] " ACTION

    if [[ "$ACTION" == "skip" ]]; then
      echo "     ⏭️  Skipped $TAB"
      continue
    fi

    FILENAME="${TAB}_${SIZE_NAME}.png"
    FILEPATH="$SIZE_DIR/$FILENAME"

    # Capture the frontmost window
    screencapture -l "$(osascript -e 'tell application "System Events" to tell process "ClarityMelt" to get id of window 1' 2>/dev/null || echo '')" -o "$FILEPATH" 2>/dev/null || \
    screencapture -w -o "$FILEPATH" 2>/dev/null || \
    screencapture -o "$FILEPATH"

    if [ -f "$FILEPATH" ]; then
      echo "     ✅ Saved: $FILEPATH"
    else
      echo "     ❌ Failed to capture screenshot"
    fi
  done
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Screenshot capture complete!"
echo "   Files saved to: $OUTPUT_DIR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# List captured files
find "$OUTPUT_DIR" -name "*.png" -exec ls -lh {} \; 2>/dev/null || echo "No PNG files found."