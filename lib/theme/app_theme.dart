import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ClarityMelt theme — Cyber Matrix aesthetic.
/// Pitch-black surface, magenta/cyan duotone, hard-edged panels.
/// Based on DESIGN.md (Cyber Matrix / alpha theme).

class AppColors {
  // ── Core palette ──
  static const primary = Color(0xFFE8FDFF);       // Headlines, core text
  static const secondary = Color(0xFF7BD3E0);      // Borders, captions, metadata
  static const tertiary = Color(0xFFFF2A9A);       // Sole interaction accent
  static const neutral = Color(0xFF070A12);         // Page foundation
  static const surface = Color(0xFF0E131F);         // Card / panel background
  static const onPrimary = Color(0xFF070A12);       // Text on tertiary buttons
  static const onSurface = Color(0xFFE8FDFF);       // Alias for readability

  // ── Semantic ──
  static const danger = Color(0xFFFF4D6A);
  static const warning = Color(0xFFF59E0B);
  static const success = Color(0xFF10B981);
  static const outline = Color(0xFF1A2035);         // Subtle borders

  // ── Provider colors ──
  static const ovh = Color(0xFF4D7CFF);
  static const hetzner = Color(0xFFFF4D6A);
  static const namecheap = Color(0xFFDE5833);
  static const cloudflare = Color(0xFFF6821F);

  // ── Code ──
  static const codeBackground = Color(0xFF111827);
  static const codeForeground = Color(0xFF7BD3E0);

  // ── Surface variants ──
  static const surfaceVariant = Color(0xFF151B2E);
  static const surfaceHover = Color(0xFF1A2238);
}

class AppTheme {
  // ── Typography ──
  static const String displayFont = 'Orbitron';
  static const String bodyFont = 'IBMPlexMono';

  static ThemeData get lightTheme => darkTheme; // Always dark

  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.neutral,
        fontFamily: bodyFont,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.tertiary,
          onPrimary: AppColors.onPrimary,
          secondary: AppColors.secondary,
          surface: AppColors.surface,
          onSurface: AppColors.primary,
          error: AppColors.danger,
        ),
        cardTheme: CardThemeData(
          color: AppColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: const BorderSide(color: AppColors.outline),
          ),
          margin: EdgeInsets.zero,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.primary,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            fontFamily: displayFont,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
            letterSpacing: 1.0,
          ),
        ),
        navigationRailTheme: NavigationRailThemeData(
          backgroundColor: AppColors.surface,
          indicatorColor: AppColors.tertiary.withValues(alpha: 0.15),
          selectedIconTheme: const IconThemeData(color: AppColors.tertiary, size: 22),
          unselectedIconTheme: IconThemeData(color: AppColors.secondary.withValues(alpha: 0.5), size: 22),
          selectedLabelTextStyle: const TextStyle(
            color: AppColors.tertiary,
            fontWeight: FontWeight.w700,
            fontSize: 11,
            fontFamily: bodyFont,
            letterSpacing: 0.5,
          ),
          unselectedLabelTextStyle: TextStyle(
            color: AppColors.secondary.withValues(alpha: 0.5),
            fontSize: 11,
            fontFamily: bodyFont,
          ),
          minWidth: 72,
          labelType: NavigationRailLabelType.all,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surfaceVariant,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(2),
            borderSide: const BorderSide(color: AppColors.outline),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(2),
            borderSide: const BorderSide(color: AppColors.outline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(2),
            borderSide: const BorderSide(color: AppColors.tertiary, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          hintStyle: TextStyle(color: AppColors.secondary.withValues(alpha: 0.4), fontFamily: bodyFont),
          labelStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.12,
            color: AppColors.secondary,
            fontFamily: bodyFont,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.tertiary,
            foregroundColor: AppColors.onPrimary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, fontFamily: bodyFont, letterSpacing: 0.5),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
            side: const BorderSide(color: AppColors.outline),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, fontFamily: bodyFont),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.secondary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
            textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, fontFamily: bodyFont),
          ),
        ),
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
          side: BorderSide.none,
          labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, fontFamily: bodyFont, letterSpacing: 0.5),
        ),
        dividerTheme: const DividerThemeData(color: AppColors.outline, thickness: 1),
        dataTableTheme: DataTableThemeData(
          headingTextStyle: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.12,
            color: AppColors.secondary,
            fontFamily: bodyFont,
          ),
          dataTextStyle: TextStyle(fontSize: 12, color: AppColors.primary, fontFamily: bodyFont),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.surfaceVariant,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          contentTextStyle: const TextStyle(color: AppColors.primary, fontFamily: bodyFont, fontSize: 13),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          titleTextStyle: const TextStyle(fontFamily: displayFont, fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.primary, letterSpacing: 0.5),
        ),
        textTheme: TextTheme(
          displayLarge: const TextStyle(fontFamily: displayFont, fontSize: 56, fontWeight: FontWeight.w800, letterSpacing: 0.02, color: AppColors.primary),
          headlineLarge: const TextStyle(fontFamily: displayFont, fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.primary),
          headlineMedium: const TextStyle(fontFamily: displayFont, fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.primary),
          titleLarge: const TextStyle(fontFamily: displayFont, fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.primary, letterSpacing: 0.5),
          titleMedium: const TextStyle(fontFamily: bodyFont, fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primary),
          bodyLarge: const TextStyle(fontFamily: bodyFont, fontSize: 14, color: AppColors.primary, height: 1.55),
          bodyMedium: const TextStyle(fontFamily: bodyFont, fontSize: 13, color: AppColors.primary, height: 1.55),
          bodySmall: TextStyle(fontFamily: bodyFont, fontSize: 11, color: AppColors.secondary, height: 1.55),
          labelLarge: const TextStyle(fontFamily: bodyFont, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.12, color: AppColors.secondary),
          labelSmall: TextStyle(fontFamily: bodyFont, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.12, color: AppColors.secondary.withValues(alpha: 0.6)),
        ),
        iconTheme: const IconThemeData(color: AppColors.secondary, size: 20),
        progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.tertiary),
      );

  // ── Helpers ──

  static Color providerColor(String provider) {
    switch (provider) {
      case 'ovh':
      case 'ovh-dedicated':
      case 'ovh-vps':
        return AppColors.ovh;
      case 'hetzner':
        return AppColors.hetzner;
      case 'namecheap':
        return AppColors.namecheap;
      case 'cloudflare':
        return AppColors.cloudflare;
      default:
        return AppColors.secondary;
    }
  }

  static String providerLabel(String provider) {
    switch (provider) {
      case 'ovh': return 'OVH';
      case 'ovh-dedicated': return 'OVH DED';
      case 'ovh-vps': return 'OVH VPS';
      case 'hetzner': return 'HETZNER';
      case 'namecheap': return 'NAMECHEAP';
      case 'cloudflare': return 'CF';
      default: return provider.toUpperCase();
    }
  }

  static Color statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'running':
      case 'active':
        return AppColors.success;
      case 'stopped':
      case 'off':
      case 'error':
        return AppColors.danger;
      default:
        return AppColors.warning;
    }
  }

  /// Tertiary-accent badge for provider
  static Widget providerBadge(String provider, {double fontSize = 10}) {
    final color = providerColor(provider);
    final label = providerLabel(provider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
      ),
      child: Text(label, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: color, fontFamily: bodyFont)),
    );
  }

  static Widget statusDot(String status, {double size = 10}) {
    final color = statusColor(status);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: (status.toLowerCase() == 'running' || status.toLowerCase() == 'active')
            ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6, spreadRadius: 1)]
            : null,
      ),
    );
  }

  static Widget recordTypeBadge(String type) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.tertiary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(type, style: const TextStyle(fontFamily: bodyFont, fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.tertiary, letterSpacing: 0.5)),
    );
  }

  static const TextStyle labelStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.12,
    color: AppColors.secondary,
    fontFamily: bodyFont,
  );
}

// ── Reusable Widgets ────────────────────────────────────────────────

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const StatCard({super.key, required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTheme.labelStyle),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: valueColor ?? AppColors.primary, fontFamily: AppTheme.displayFont)),
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const EmptyState({super.key, required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: AppColors.secondary.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.primary, fontFamily: AppTheme.displayFont)),
            const SizedBox(height: 8),
            Text(subtitle, style: const TextStyle(fontSize: 13, color: AppColors.secondary, fontFamily: AppTheme.bodyFont), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class ErrorBanner extends StatelessWidget {
  final String message;
  const ErrorBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.danger, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 13, color: AppColors.danger, fontFamily: AppTheme.bodyFont))),
        ],
      ),
    );
  }
}

class CodeBlock extends StatelessWidget {
  final String text;
  final Color? backgroundColor;
  final Color? textColor;

  const CodeBlock({super.key, required this.text, this.backgroundColor, this.textColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.codeBackground,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: AppColors.outline),
      ),
      child: Text(text, style: TextStyle(fontFamily: AppTheme.bodyFont, fontSize: 12, color: textColor ?? AppColors.codeForeground)),
    );
  }
}

class NeonDivider extends StatelessWidget {
  const NeonDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: AppColors.tertiary.withValues(alpha: 0.15));
  }
}

class TertiaryButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Widget child;

  const TertiaryButton({super.key, required this.onPressed, required this.child});

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.tertiary,
        foregroundColor: AppColors.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
      ),
      child: child,
    );
  }
}