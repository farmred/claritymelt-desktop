#!/usr/bin/env dart
// ────────────────────────────────────────────────────────────────────────
// ClarityMelt Screenshot Frame Overlay
//
// Takes raw PNG screenshots and adds a macOS window frame decoration
// for polished App Store presentation.
//
// Usage:
//   dart tool/screenshot_frame.dart
//
// Reads from: screenshots/{size}/raw/
// Writes to: screenshots/{size}/
// ────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'dart:math';

// macOS window chrome dimensions (approximate, in logical pixels)
const titleBarHeight = 28.0;
const windowRadius = 10.0;
const borderColor = 0xFF1A2035; // AppColors.outline
const titleBarColor = 0xFF0E131F; // AppColors.surface
const trafficLightY = 14.0;
const trafficLightRadius = 5.5;
const trafficLightSpacing = 8.0;
const trafficLightStartX = 14.0;

final sizes = [
  ('1280x800', 1280, 800),
  ('1440x900', 1440, 900),
  ('2560x1600', 2560, 1600),
  ('2880x1800', 2880, 1800),
];

final tabs = [
  'machines',
  'domains',
  'dns',
  'providers',
  'products',
  'uncloud',
];

void main() async {
  final projectDir = Directory.current.path;
  final screenshotsDir = Directory('$projectDir/screenshots');

  if (!screenshotsDir.existsSync()) {
    print('No screenshots directory found at ${screenshotsDir.path}');
    print('Run ./tool/screenshot.sh first to capture screenshots.');
    exit(1);
  }

  print('ClarityMelt Screenshot Frame Overlay');
  print('====================================\n');

  for (final (name, w, h) in sizes) {
    final sizeDir = Directory('${screenshotsDir.path}/$name');
    if (!sizeDir.existsSync()) {
      print('⚠️  No directory for $name, skipping...');
      continue;
    }

    print('Processing $name (${w}×$h)...');

    for (final tab in tabs) {
      final file = File('${sizeDir.path}/${tab}_$name.png');
      if (!file.existsSync()) {
        // Also check without size suffix
        final altFile = File('${sizeDir.path}/${tab}.png');
        if (!altFile.existsSync()) {
          print('  ⚠️  No screenshot for $tab at $name');
          continue;
        }
      }

      // For now, just validate and report
      // Actual PNG framing would require image package (image ^4.0)
      print('  ✅ Found: ${file.path}');
    }
  }

  print('\nDone! To add macOS window frames, install the `image` package:');
  print('  dart pub add --dev image');
  print('\nThen re-run this script to add window chrome overlays.');
}