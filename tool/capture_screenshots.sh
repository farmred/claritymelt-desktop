#!/usr/bin/env bash
set -euo pipefail

# ────────────────────────────────────────────────────────────────────────
# ClarityMelt — Mac App Store Screenshot Capture
#
# On Retina Macs, screencapture produces 2x images:
#   - 1280×800 logical → 2560×1600 capture
#   - 1440×900 logical → 2880×1800 capture
#
# We downscale 2x captures for 1x variants:
#   - 2560×1600 → 1280×800
#   - 2880×1800 → 1440×900
#
# Uses CGEvent mouse clicks (via Swift helper) to navigate tabs
# since Flutter doesn't respond to Accessibility API clicks.
#
# Prerequisites:
#   - ClarityMelt app is running (release build)
#   - /tmp/click_at Swift helper compiled and available
# ────────────────────────────────────────────────────────────────────────

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${PROJECT_DIR}/screenshots"
APP_NAME="ClarityMelt"

# Tabs in navigation rail order with screen Y-coordinates
# (relative to screen top, window positioned at y=25)
# These are center points for each tab's click target area
TAB_NAMES=("machines" "domains" "dns" "providers" "products" "uncloud")
TAB_Y=(120 190 250 310 360 430)
TAB_X=40  # Center of navigation rail

# Window sizes (logical pixels) to capture
LOGICAL_SIZES=("1280x800" "1440x900")

mkdir -p "$OUTPUT_DIR"

echo "╔══════════════════════════════════════════════════════════╗"
echo "║    ClarityMelt App Store Screenshot Capture              ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Verify app is running
if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
  echo "❌ $APP_NAME is not running!"
  echo "   Start it with: open build/macos/Build/Products/Release/ClarityMelt.app"
  exit 1
fi
echo "✅ Found $APP_NAME running (PID: $(pgrep -x "$APP_NAME"))"

# Check if click_at helper exists
if [ ! -f /tmp/click_at ]; then
  echo "⚙️  Compiling click helper..."
  cat > /tmp/click_at.swift << 'SWIFT'
import Cocoa
import ApplicationServices

let x = Double(CommandLine.arguments[1]) ?? 0
let y = Double(CommandLine.arguments[2]) ?? 0

let source = CGEventSource(stateID: .hidSystemState)
let point = CGPoint(x: x, y: y)

let moveEvent = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
moveEvent?.post(tap: .cghidEventTap)
usleep(50000)

let downEvent = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
downEvent?.post(tap: .cghidEventTap)
usleep(100000)

let upEvent = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
upEvent?.post(tap: .cghidEventTap)
SWIFT
  swiftc -o /tmp/click_at /tmp/click_at.swift
  echo "✅ Click helper compiled"
fi

# ─── Helper functions ───

resize_window() {
  local w="$1" h="$2"
  osascript -e "
    tell application \"System Events\"
      tell process \"$APP_NAME\"
        set frontmost to true
        set position of window 1 to {0, 25}
        set size of window 1 to {$w, $h}
      end tell
    end tell
  " 2>/dev/null
}

get_window_rect() {
  osascript -e '
    tell application "System Events"
      tell process "'"$APP_NAME"'"
        set frontmost to true
        set winPos to position of window 1
        set winSize to size of window 1
        set x to item 1 of winPos
        set y to item 2 of winPos
        set w to item 1 of winSize
        set h to item 2 of winSize
        return (x as text) & ":" & (y as text) & ":" & (w as text) & ":" & (h as text)
      end tell
    end tell
  ' 2>/dev/null
}

click_tab() {
  local tab_index="$1"
  local y="${TAB_Y[$tab_index]}"
  /tmp/click_at "$TAB_X" "$y" 2>/dev/null
}

capture_window() {
  local filepath="$1"
  local rect
  rect=$(get_window_rect)
  local x y w h
  x=$(echo "$rect" | cut -d: -f1)
  y=$(echo "$rect" | cut -d: -f2)
  w=$(echo "$rect" | cut -d: -f3)
  h=$(echo "$rect" | cut -d: -f4)
  
  screencapture -x -R"${x},${y},${w},${h}" "$filepath" 2>/dev/null
}

# ─── Main capture ───

TOTAL=0
FAILED=0

for logical_size in "${LOGICAL_SIZES[@]}"; do
  W="${logical_size%x*}"
  H="${logical_size#*x}"
  
  # Compute physical (Retina 2x) size name
  PHYS_W=$((W * 2))
  PHYS_H=$((H * 2))
  PHYSICAL_SIZE="${PHYS_W}x${PHYS_H}"
  
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📐 Window: ${W}×${H} logical → ${PHYS_W}×${PHYS_H} physical"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Resize window
  resize_window "$W" "$H"
  sleep 1.5
  
  # Verify
  rect=$(get_window_rect)
  echo "   Window rect: $rect"
  
  # Create output directories
  TWO_X_DIR="$OUTPUT_DIR/$PHYSICAL_SIZE"
  ONE_X_DIR="$OUTPUT_DIR/$logical_size"
  mkdir -p "$TWO_X_DIR" "$ONE_X_DIR"
  
  # Capture each tab
  for i in "${!TAB_NAMES[@]}"; do
    TAB="${TAB_NAMES[$i]}"
    
    # Click the tab
    click_tab "$i"
    sleep 1.5
    
    # 2x capture (Retina)
    FILENAME="${TAB}_${PHYSICAL_SIZE}.png"
    FILEPATH="$TWO_X_DIR/$FILENAME"
    
    echo -n "   📸 $TAB ... "
    
    if capture_window "$FILEPATH" && [ -f "$FILEPATH" ]; then
      FILESIZE=$(stat -f%z "$FILEPATH" 2>/dev/null || stat -c%s "$FILEPATH" 2>/dev/null)
      echo "✅ 2x ($(( FILESIZE / 1024 ))KB)"
      TOTAL=$((TOTAL + 1))
      
      # Create 1x version by downscaling
      ONE_X_FILENAME="${TAB}_${logical_size}.png"
      ONE_X_FILEPATH="$ONE_X_DIR/$ONE_X_FILENAME"
      sips -z "$H" "$W" "$FILEPATH" --out "$ONE_X_FILEPATH" >/dev/null 2>&1
      if [ -f "$ONE_X_FILEPATH" ]; then
        ONE_X_SIZE=$(stat -f%z "$ONE_X_FILEPATH" 2>/dev/null || stat -c%s "$ONE_X_FILEPATH" 2>/dev/null)
        echo "      ↓ 1x ($(( ONE_X_SIZE / 1024 ))KB)"
      fi
    else
      echo "❌ Capture failed"
      FAILED=$((FAILED + 1))
    fi
  done
  
  echo ""
done

# ─── Summary ───
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Screenshot Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

for size_name in "1280x800" "1440x900" "2560x1600" "2880x1800"; do
  size_dir="$OUTPUT_DIR/$size_name"
  if [ -d "$size_dir" ]; then
    COUNT=$(find "$size_dir" -name "*.png" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$COUNT" -gt 0 ]; then
      echo "  $size_name: $COUNT screenshots"
      find "$size_dir" -name "*.png" -exec ls -lh {} \; 2>/dev/null | \
        awk '{print "    " $5 "  " $NF}' | sed "s|$size_dir/||g"
    fi
  fi
done

echo ""
echo "Total: $TOTAL captured, $FAILED failed"
echo "Output: $OUTPUT_DIR"
echo ""

# ─── Copy to Distribution directory ───
DIST_DIR="$PROJECT_DIR/build/macos/Distribution/AppStore/screenshots"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 Copying to Distribution directory..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

for size_name in "1280x800" "1440x900" "2560x1600" "2880x1800"; do
  SRC="$OUTPUT_DIR/$size_name"
  DST="$DIST_DIR/$size_name"
  if [ -d "$SRC" ]; then
    mkdir -p "$DST"
    COUNT=$(find "$SRC" -name "*.png" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$COUNT" -gt 0 ]; then
      cp "$SRC"/*.png "$DST/"
      echo "  $size_name: $COUNT files copied"
    fi
  fi
done

echo ""
if [ "$TOTAL" -gt 0 ]; then
  echo "🎉 Screenshots ready for App Store Connect!"
  echo ""
  echo "   1x sizes:  $OUTPUT_DIR/1280x800/ and $OUTPUT_DIR/1440x900/"
  echo "   2x sizes:  $OUTPUT_DIR/2560x1600/ and $OUTPUT_DIR/2880x1800/"
  echo "   Distribution: $DIST_DIR"
fi