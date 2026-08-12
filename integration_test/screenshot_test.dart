import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';

import 'package:claritymelt_desktop/main.dart' as app;
import 'package:claritymelt_desktop/models/models.dart';
import 'package:claritymelt_desktop/providers/app_providers.dart';
import 'package:claritymelt_desktop/theme/app_theme.dart';

/// Screenshot sizes for Mac App Store distribution.
const List<({String name, int width, int height})> screenshotSizes = [
  (name: '1280x800', width: 1280, height: 800),
  (name: '1440x900', width: 1440, height: 900),
  (name: '2560x1600', width: 2560, height: 1600),
  (name: '2880x1800', width: 2880, height: 1800),
];

/// Tab definitions matching MainScaffold._destinations.
const List<({String name, int index, IconData icon})> tabs = [
  (name: 'machines', index: 0, icon: Icons.computer_outlined),
  (name: 'domains', index: 1, icon: Icons.language_outlined),
  (name: 'dns', index: 2, icon: Icons.dns_outlined),
  (name: 'providers', index: 3, icon: Icons.vpn_key_outlined),
  (name: 'products', index: 4, icon: Icons.inventory_2_outlined),
  (name: 'uncloud', index: 5, icon: Icons.cloud_outlined),
];

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Read env vars for selective capture (useful for parallel CI)
  final targetSize = Platform.environment['SCREENSHOT_SIZE'];
  final targetTab = Platform.environment['SCREENSHOT_TAB'];
  final outputDir = Platform.environment['SCREENSHOT_DIR'] ??
      '${Directory.current.path}/screenshots';

  group('App Store Screenshots', () {
    for (final size in screenshotSizes) {
      if (targetSize != null && targetSize != size.name) continue;

      testWidgets('Capture ${size.name} screenshots', (tester) async {
        // ── 1. Set window size ──
        await windowManager.setSize(
          Size(size.width.toDouble(), size.height.toDouble()),
        );
        await tester.pumpAndSettle(const Duration(milliseconds: 500));

        // ── 2. Launch the app ──
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 3));

        // ── 3. Navigate to each tab and capture ──
        for (final tab in tabs) {
          if (targetTab != null && targetTab != tab.name) continue;

          // Find and tap the navigation rail destination
          // The NavigationRail renders destinations as a column of
          // GestureDetector-wrapped icons. We find by icon.
          final iconFinder = find.byIcon(tab.icon);

          if (iconFinder.evaluate().isNotEmpty) {
            await tester.tap(iconFinder.first);
            await tester.pumpAndSettle(const Duration(seconds: 2));
          }

          // ── 4. Capture screenshot ──
          final dir = Directory('$outputDir/${size.name}');
          if (!dir.existsSync()) {
            dir.createSync(recursive: true);
          }

          final filePath = '${dir.path}/${tab.name}.png';

          // Use binding.takeScreenshot which returns raw RGBA bytes,
          // then we convert to PNG ourselves for better control.
          // Alternatively, just use the integration_test binding capture.
          await binding.takeScreenshot(filePath);

          // Small delay between captures
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }

        // ── 5. Also capture the default/landing view ──
        // Navigate back to machines tab (default)
        final machinesIcon = find.byIcon(Icons.computer_outlined);
        if (machinesIcon.evaluate().isNotEmpty) {
          await tester.tap(machinesIcon.first);
          await tester.pumpAndSettle();
        }
      });
    }
  });
}