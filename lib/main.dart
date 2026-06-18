import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'database/database.dart';
import 'providers/app_providers.dart';
import 'theme/app_theme.dart';
import 'screens/machines_screen.dart';
import 'screens/machine_detail_screen.dart';
import 'screens/domains_screen.dart';
import 'screens/dns_manager_screen.dart';
import 'screens/providers_screen.dart';
import 'screens/products_screen.dart';
import 'screens/uncloud_screen.dart';
import 'models/models.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configure window manager for macOS desktop
  await windowManager.ensureInitialized();
  WindowOptions windowOptions = const WindowOptions(
    size: Size(1200, 800),
    minimumSize: Size(800, 600),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
    title: 'ClarityMelt',
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  // Initialize database
  final db = AppDatabase();

  runApp(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const ClarityMeltApp(),
    ),
  );
}

class ClarityMeltApp extends ConsumerWidget {
  const ClarityMeltApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'ClarityMelt',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const MainScaffold(),
    );
  }
}

class MainScaffold extends ConsumerStatefulWidget {
  const MainScaffold({super.key});

  @override
  ConsumerState<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends ConsumerState<MainScaffold> {
  int _selectedIndex = 0;

  void _navigateToTab(int index) {
    setState(() => _selectedIndex = index);
  }

  static const List<NavigationRailDestination> _destinations = [
    NavigationRailDestination(
      icon: Icon(Icons.computer_outlined),
      selectedIcon: Icon(Icons.computer),
      label: Text('Machines'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.language_outlined),
      selectedIcon: Icon(Icons.language),
      label: Text('Domains'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.dns_outlined),
      selectedIcon: Icon(Icons.dns),
      label: Text('DNS'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.vpn_key_outlined),
      selectedIcon: Icon(Icons.vpn_key),
      label: Text('Providers'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.inventory_2_outlined),
      selectedIcon: Icon(Icons.inventory_2),
      label: Text('Products'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.cloud_outlined),
      selectedIcon: Icon(Icons.cloud),
      label: Text('Uncloud'),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final screens = <Widget>[
      MachinesScreen(onNavigateToDns: () => _navigateToTab(2)),
      DomainsScreen(onNavigateToDns: () => _navigateToTab(2)),
      const DnsManagerScreen(),
      const ProvidersScreen(),
      const ProductsScreen(),
      const UncloudScreen(),
    ];

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() => _selectedIndex = index);
            },
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
              child: Column(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Center(
                      child: Text(
                        'C',
                        style: TextStyle(
                          color: AppColors.onPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'ClarityMelt',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            destinations: _destinations,
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: screens[_selectedIndex]),
        ],
      ),
    );
  }
}

/// Navigate to machine detail screen.
void navigateToMachineDetail(BuildContext context, MachineInfo machine, {void Function(DomainInfo)? onNavigateToDns}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (context) => MachineDetailScreen(machine: machine, onNavigateToDns: onNavigateToDns),
    ),
  );
}