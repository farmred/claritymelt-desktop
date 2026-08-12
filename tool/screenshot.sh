#!/usr/bin/env bash
set -euo pipefail

# ────────────────────────────────────────────────────────────────────────
# ClarityMelt — Mac App Store Screenshot Generator
#
# Generates screenshots at standard macOS App Store dimensions:
#   • 1280 × 800   (MacBook Air 13" non-Retina)
#   • 1440 × 900   (MacBook Air 13" scaled / 15" non-Retina)
#   • 2560 × 1600  (MacBook Air/Pro 13" Retina @2x)
#   • 2880 × 1800  (MacBook Pro 15/16" Retina @2x)
#
# Modes:
#   auto  — Run integration test that launches the app at each size
#   manual — Interactive: resize window + screencapture per tab
#   quick  — Capture the currently-running app window at each size
#
# Usage:
#   ./tool/screenshot.sh                    # auto mode, all sizes
#   ./tool/screenshot.sh auto 1280x800      # auto mode, one size
#   ./tool/screenshot.sh manual             # interactive manual capture
#   ./tool/screenshot.sh quick               # capture active window
# ────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${PROJECT_DIR}/screenshots"
APP_NAME="ClarityMelt"

SIZES=("1280x800" "1440x900" "2560x1600" "2880x1800")
TABS=("machines" "domains" "dns" "providers" "products" "uncloud")

MODE="${1:-auto}"
TARGET_SIZE="${2:-all}"

# Parse W×H from size name (e.g. "1280x800" → 1280 800)
parse_size() {
  local size="$1"
  echo "${size%x*} ${size#*x}"
}

mkdir -p "$OUTPUT_DIR"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║       ClarityMelt Screenshot Generator                    ║"
echo "║       Output: $OUTPUT_DIR"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# ─── AUTO MODE ──────────────────────────────────────────────────────
auto_capture() {
  echo "🤖 Auto mode: running Flutter integration test..."
  echo ""

  cd "$PROJECT_DIR"

  # Ensure integration_test dep is present
  if ! grep -q "integration_test" pubspec.yaml; then
    echo "📦 Adding integration_test dependency..."
    flutter pub add --dev integration_test
  fi

  if [[ "$TARGET_SIZE" != "all" ]]; then
    SCREENSHOT_SIZE="$TARGET_SIZE" \
      flutter test integration_test/screenshot_test.dart \
        -d macos \
        --dart-define=SCREENSHOT_SIZE="$TARGET_SIZE" \
        --dart-define=SCREENSHOT_DIR="$OUTPUT_DIR"
  else
    flutter test integration_test/screenshot_test.dart \
      -d macos \
      --dart-define=SCREENSHOT_DIR="$OUTPUT_DIR"
  fi
}

# ─── MANUAL MODE ─────────────────────────────────────────────────────
manual_capture() {
  echo "🖥️  Manual mode: interactive screenshot capture"
  echo ""
  echo "⚠️  Make sure ClarityMelt is running!"
  echo ""
  read -p "Press Enter to continue (Ctrl+C to cancel)..."

  # Check if app is running
  if ! pgrep -x "$APP_NAME" >/dev/null 2>&1 && \
     ! pgrep -f "claritymelt_desktop" >/dev/null 2>&1; then
    echo "❌ $APP_NAME doesn't appear to be running."
    echo "   Start it with: flutter run -d macos"
    echo ""
    read -p "Continue anyway? (y/N) " CONFIRM
    [[ "${CONFIRM,,}" != "y" ]] && exit 1
  fi

  for SIZE in $( [[ "$TARGET_SIZE" == "all" ]] && echo "${SIZES[@]}" || echo "$TARGET_SIZE" ); do
    read -r W H <<< "$(parse_size "$SIZE")"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📸 ${SIZE} (${W}×${H})"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    SIZE_DIR="$OUTPUT_DIR/$SIZE"
    mkdir -p "$SIZE_DIR"

    # Resize window via AppleScript
    osascript -e "
      tell application \"System Events\"
        set appName to \"$APP_NAME\"
        if (name of processes) contains appName then
          tell process appName
            set frontmost to true
            set position of window 1 to {0, 0}
            set size of window 1 to {$W, $H}
          end tell
        end if
      end tell
    " 2>/dev/null || {
      echo "⚠️  Could not resize window. Please resize manually to ${W}×${H}."
      echo "   Then press Enter to continue..."
      read
    }

    sleep 1

    for TAB in "${TABS[@]}"; do
      echo ""
      echo "  📍 Navigate to the '$TAB' tab in the app."
      echo "     Then press Enter to capture (or type 'skip'):"
      read -p "     [Enter/skip] " ACTION

      [[ "$ACTION" == "skip" ]] && echo "     ⏭️  Skipped" && continue

      FILENAME="${TAB}_${SIZE}.png"
      FILEPATH="$SIZE_DIR/$FILENAME"

      # Try window-specific capture first, fall back to interactive
      screencapture -w -o "$FILEPATH" 2>/dev/null || \
      screencapture -o "$FILEPATH" 2>/dev/null || \
      echo "     ❌ Capture failed"

      if [ -f "$FILEPATH" ]; then
        FILESIZE=$(stat -f%z "$FILEPATH" 2>/dev/null || stat -c%s "$FILEPATH" 2>/dev/null)
        echo "     ✅ Saved: $FILEPATH ($(( FILESIZE / 1024 ))KB)"
      fi
    done
  done
}

# ─── QUICK MODE ──────────────────────────────────────────────────────
quick_capture() {
  echo "⚡ Quick mode: capture active ClarityMelt window at each size"
  echo ""
  echo "⚠️  Make sure ClarityMelt is running!"
  echo ""

  # Check if app is running
  local APP_PID=""
  APP_PID=$(pgrep -f "claritymelt_desktop" 2>/dev/null || true)
  if [ -z "$APP_PID" ]; then
    APP_PID=$(pgrep -x "$APP_NAME" 2>/dev/null || true)
  fi

  if [ -z "$APP_PID" ]; then
    echo "❌ $APP_NAME doesn't appear to be running."
    echo "   Start it with: flutter run -d macos"
    exit 1
  fi

  for SIZE in $( [[ "$TARGET_SIZE" == "all" ]] && echo "${SIZES[@]}" || echo "$TARGET_SIZE" ); do
    read -r W H <<< "$(parse_size "$SIZE")"

    SIZE_DIR="$OUTPUT_DIR/$SIZE"
    mkdir -p "$SIZE_DIR"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📸 Resizing to ${SIZE} (${W}×${H})"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Resize via AppleScript
    osascript -e "
      tell application \"System Events\"
        set appName to \"$APP_NAME\"
        if (name of processes) contains appName then
          tell process appName
            set frontmost to true
            set position of window 1 to {0, 0}
            set size of window 1 to {$W, $H}
          end tell
        end if
      end tell
    " 2>/dev/null

    sleep 2

    for TAB in "${TABS[@]}"; do
      echo "  Navigate to '$TAB' tab..."
      read -p "  Press Enter to capture (or type 'skip'): " ACTION
      [[ "$ACTION" == "skip" ]] && continue

      FILENAME="${TAB}_${SIZE}.png"
      FILEPATH="$SIZE_DIR/$FILENAME"

      # Capture the active window
      screencapture -w -o "$FILEPATH" 2>/dev/null || \
      screencapture -o "$FILEPATH"

      [ -f "$FILEPATH" ] && echo "  ✅ $FILEPATH" || echo "  ❌ Failed"
    done
  done
}

# ─── RUN ─────────────────────────────────────────────────────────────
case "$MODE" in
  auto)
    auto_capture
    ;;
  manual)
    manual_capture
    ;;
  quick)
    quick_capture
    ;;
  *)
    echo "Unknown mode: $MODE"
    echo "Usage: $0 [auto|manual|quick] [SIZE]"
    echo ""
    echo "Modes:"
    echo "  auto   — Run Flutter integration test (automated)"
    echo "  manual — Interactive: resize + capture per tab"
    echo "  quick  — Capture active window at each size"
    echo ""
    echo "Sizes: 1280x800 1440x900 2560x1600 2880x1800 (or 'all')"
    exit 1
    ;;
esac

# ─── SUMMARY ─────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Screenshot Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

TOTAL=0
for SIZE in "${SIZES[@]}"; do
  if [[ "$TARGET_SIZE" != "all" && "$TARGET_SIZE" != "$SIZE" ]]; then
    continue
  fi

  SIZE_DIR="$OUTPUT_DIR/$SIZE"
  if [ -d "$SIZE_DIR" ]; then
    COUNT=$(find "$SIZE_DIR" -name "*.png" 2>/dev/null | wc -l | tr -d ' ')
    echo "  $SIZE: $COUNT screenshots"
    TOTAL=$((TOTAL + COUNT))

    # List files with sizes
    find "$SIZE_DIR" -name "*.png" -exec ls -lh {} \; 2>/dev/null | \
      awk '{print "    " $NF "  (" $5 ")"}' | sed "s|$SIZE_DIR/||"
  else
    echo "  $SIZE: (no directory)"
  fi
done

echo ""
echo "Total: $TOTAL screenshots in $OUTPUT_DIR"
echo ""

if [ "$TOTAL" -eq 0 ]; then
  echo "💡 No screenshots captured. Try:"
  echo ""
  echo "  # Option 1: Run the app and capture interactively"
  echo "  flutter run -d macos"
  echo "  ./tool/screenshot.sh manual"
  echo ""
  echo "  # Option 2: Quick window capture"
  echo "  flutter run -d macos"
  echo "  ./tool/screenshot.sh quick"
  echo ""
  echo "  # Option 3: Automated integration test"
  echo "  ./tool/screenshot.sh auto"
fi