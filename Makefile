.PHONY: run build generate deps screenshots clean-screenshots package archive dmg notarize metadata check

# ClarityMelt Desktop

run:
	flutter run -d macos

build:
	flutter build macos --release

# ── Code generation ───────────────────────────────────────────────────

generate:
	dart run build_runner build --delete-conflicting-outputs

deps:
	flutter pub get

# ── Screenshots ──────────────────────────────────────────────────────
# Generate Mac App Store screenshots at standard distribution sizes:
#   1280×800, 1440×900, 2560×1600, 2880×1800

screenshots:
	@./tool/screenshot.sh auto

screenshots-manual:
	@./tool/screenshot.sh manual

screenshots-quick:
	@./tool/screenshot.sh quick

clean-screenshots:
	@rm -rf screenshots/
	@echo "Screenshots cleaned."

# ── Packaging & Distribution ──────────────────────────────────────────

check:
	@./tool/package.sh check

package:
	@./tool/package.sh all

archive:
	@./tool/package.sh archive

dmg:
	@./tool/package.sh dmg

notarize:
	@./tool/package.sh notarize

metadata:
	@./tool/package.sh metadata

# ── Clean ─────────────────────────────────────────────────────────────

clean:
	flutter clean
	rm -rf build/